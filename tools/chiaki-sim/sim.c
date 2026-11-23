// SPDX-License-Identifier: AGPL-3.0-only
//
// libchiaki'nin görüntü alıcısını (videoreceiver.c) ve sıralama kuyruğunu (reorderqueue.c) GERÇEK kaynaklarıyla,
// benzetilmiş bir PS5 ve kayıplı bir ağla çalıştırır. third-party/patches yamalarının paket kaybındaki davranışını
// (toparlanma süresi, IDR isteği sayısı, oturumun düşüp düşmediği) yamasız kaynakla karşılaştırmak içindir.
// Çalıştırma: tools/chiaki-sim/run.sh
//
// Gerçek olanlar: chiaki_video_receiver_av_packet ve çağırdıkları, chiaki_reorder_queue_*, takion.c'deki
// takion_av_queue_flush_with_timeout'un birebir kopyası, takionsendbuffer.c'nin kuralları (200 ms'de yeniden gönderme,
// 25 deneme, taşan paket izlenmez).
// Benzetilenler: saat, ağ (kayıp, sıra bozulması), FEC (yeterli birim geldiyse kare tamamlanır), dilim başlığı ve PS5.
// PS5 varsayımları: IDRREQUEST alınca sıradaki kare IDR olur; CORRUPTFRAME ile bildirilen kareleri ve onlara dayanan
// kareleri başvuru almaz, son 16 karede sağlam kare yoksa IDR gönderir; güvenilir paketleri sırayla onaylar (SCTP'deki birikimli onay).

#include <chiaki/videoreceiver.h>
#include <chiaki/session.h>
#include <chiaki/reorderqueue.h>
#include <chiaki/streamconnection.h>
#include <chiaki/time.h>

#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#ifndef SEND_BUFFER_SIZE
#define SEND_BUFFER_SIZE 16
#endif
#ifndef VARIANT
#define VARIANT "?"
#endif

// --- saat ve rastgele ---

static uint64_t now_us;

uint64_t chiaki_time_now_monotonic_us(void) { return now_us; }

static uint64_t rng_state;
static double rnd(void)
{
	rng_state ^= rng_state << 13;
	rng_state ^= rng_state >> 7;
	rng_state ^= rng_state << 17;
	return (double)(rng_state >> 11) / (double)(1ULL << 53);
}
static double rnd_exp(double mean) { return -mean * log(1.0 - rnd() * 0.999999); }

// --- libchiaki'nin benzetimde gerekmeyen parçaları ---

static int verbose;
void chiaki_log(ChiakiLog *log, ChiakiLogLevel level, const char *fmt, ...)
{
	(void)log;
	if(!verbose || level == CHIAKI_LOG_VERBOSE)
		return;
	va_list args;
	va_start(args, fmt);
	printf("%10.3f ", now_us / 1e6);
	vprintf(fmt, args);
	printf("\n");
	va_end(args);
}
const char *chiaki_error_string(ChiakiErrorCode code) { (void)code; return "error"; }
ChiakiErrorCode chiaki_mutex_init(ChiakiMutex *mutex, bool rec) { (void)mutex; (void)rec; return CHIAKI_ERR_SUCCESS; }
ChiakiErrorCode chiaki_mutex_fini(ChiakiMutex *mutex) { (void)mutex; return CHIAKI_ERR_SUCCESS; }
ChiakiErrorCode chiaki_mutex_lock(ChiakiMutex *mutex) { (void)mutex; return CHIAKI_ERR_SUCCESS; }
ChiakiErrorCode chiaki_mutex_unlock(ChiakiMutex *mutex) { (void)mutex; return CHIAKI_ERR_SUCCESS; }

static struct
{
	uint64_t fec_failures, idr_requests, corrupt_reports, idr_received, pictures, overflows, gave_up, resends;
	uint64_t freezes, freeze_us_total, freeze_us_max, watchdog_drops, down_us, queue_drops, units_sent, units_lost;
	uint64_t recover_count, recover_us_total, recover_us_max;
} stats;

void chiaki_session_send_event(ChiakiSession *session, ChiakiEvent *event)
{
	(void)session;
	if(event->type == CHIAKI_EVENT_VIDEO_FEC_FAILURE)
		stats.fec_failures++;
}

// --- FEC: yeterli birim geldiyse kare tamamlanır ---

#define KIND_P 0
#define KIND_IDR 1
static uint8_t frame_kind[0x10000];
static uint8_t frame_reference[0x10000]; // P karesi: kaç kare geriye başvuruyor (0: bir önceki)
static uint8_t fp_seen[2048];
static ChiakiSeqNum16 fp_frame;
static uint8_t fp_out[2];

void chiaki_frame_processor_init(ChiakiFrameProcessor *fp, ChiakiLog *log) { memset(fp, 0, sizeof(*fp)); fp->log = log; }
void chiaki_frame_processor_fini(ChiakiFrameProcessor *fp) { (void)fp; }
void chiaki_frame_processor_report_packet_stats(ChiakiFrameProcessor *fp, ChiakiPacketStats *packet_stats) { (void)fp; (void)packet_stats; }
ChiakiErrorCode chiaki_frame_processor_alloc_frame(ChiakiFrameProcessor *fp, ChiakiTakionAVPacket *packet)
{
	fp->units_source_expected = packet->units_in_frame_total - packet->units_in_frame_fec;
	fp->units_fec_expected = packet->units_in_frame_fec;
	fp->units_source_received = fp->units_fec_received = 0;
	fp->flushed = false;
	fp_frame = packet->frame_index;
	memset(fp_seen, 0, sizeof(fp_seen));
	return CHIAKI_ERR_SUCCESS;
}
ChiakiErrorCode chiaki_frame_processor_put_unit(ChiakiFrameProcessor *fp, ChiakiTakionAVPacket *packet)
{
	if(packet->frame_index != fp_frame || packet->unit_index >= packet->units_in_frame_total || fp_seen[packet->unit_index])
		return CHIAKI_ERR_INVALID_DATA;
	fp_seen[packet->unit_index] = 1;
	if(packet->unit_index < fp->units_source_expected)
		fp->units_source_received++;
	else
		fp->units_fec_received++;
	return CHIAKI_ERR_SUCCESS;
}
ChiakiFrameProcessorFlushResult chiaki_frame_processor_flush(ChiakiFrameProcessor *fp, uint8_t **frame, size_t *frame_size)
{
	if(fp->units_source_expected == 0 || fp->flushed)
		return CHIAKI_FRAME_PROCESSOR_FLUSH_RESULT_FAILED;
	fp->flushed = true;
	fp_out[0] = frame_kind[fp_frame];
	fp_out[1] = frame_reference[fp_frame];
	*frame = fp_out;
	*frame_size = sizeof(fp_out);
	if(fp->units_source_received >= fp->units_source_expected)
		return CHIAKI_FRAME_PROCESSOR_FLUSH_RESULT_SUCCESS;
	return fp->units_source_received + fp->units_fec_received >= fp->units_source_expected
		? CHIAKI_FRAME_PROCESSOR_FLUSH_RESULT_FEC_SUCCESS : CHIAKI_FRAME_PROCESSOR_FLUSH_RESULT_FEC_FAILED;
}

void chiaki_bitstream_init(ChiakiBitstream *bitstream, ChiakiLog *log, ChiakiCodec codec) { (void)bitstream; (void)log; (void)codec; }
bool chiaki_bitstream_header(ChiakiBitstream *bitstream, uint8_t *data, unsigned size) { (void)bitstream; (void)data; (void)size; return true; }
bool chiaki_bitstream_slice(ChiakiBitstream *bitstream, uint8_t *data, unsigned size, ChiakiBitstreamSlice *slice)
{
	(void)bitstream; (void)size;
	slice->slice_type = data[0] == KIND_IDR ? CHIAKI_BITSTREAM_SLICE_I : CHIAKI_BITSTREAM_SLICE_P;
	slice->reference_frame = data[1];
	return true;
}
// H.264'te libchiaki başvuru karesini değiştiremez (bitstream.c)
bool chiaki_bitstream_slice_set_reference_frame(ChiakiBitstream *bitstream, uint8_t *data, unsigned size, unsigned reference_frame)
{
	(void)bitstream; (void)data; (void)size; (void)reference_frame;
	return false;
}

// --- ağ ---

typedef struct
{
	const char *name;
	double loss;          // sürekli kayıp oranı
	double burst_every_s; // patlamalar arası ortalama süre (0: patlama yok)
	double burst_len_s;   // patlamanın ortalama süresi
	double burst_loss;    // patlama sırasındaki kayıp oranı
	double reorder;       // paketin gecikip sırasının bozulma olasılığı
} Scenario;

static const Scenario *scenario;
static uint64_t burst_begin_us, burst_end_us;

static void burst_schedule(uint64_t from_us)
{
	if(scenario->burst_every_s <= 0)
	{
		burst_begin_us = burst_end_us = UINT64_MAX;
		return;
	}
	burst_begin_us = from_us + (uint64_t)(rnd_exp(scenario->burst_every_s) * 1e6);
	burst_end_us = burst_begin_us + (uint64_t)(rnd_exp(scenario->burst_len_s) * 1e6) + 1000;
}

static bool lost_at(uint64_t t_us)
{
	while(t_us >= burst_end_us)
		burst_schedule(burst_end_us);
	double p = t_us >= burst_begin_us ? scenario->burst_loss : scenario->loss;
	return rnd() < p;
}

// --- güvenilir gönderme tamponu (takionsendbuffer.c'nin kuralları) ve PS5 ---

#define MSG_HEARTBEAT 0
#define MSG_CORRUPT 1
#define MSG_IDR 2
#define RESEND_TIMEOUT_US 200000
#define RESEND_WAKEUP_US 100000
#define RESEND_TRIES_MAX 25
#define LINK_DELAY_US 5000

typedef struct { uint32_t seq; uint8_t type; uint16_t start, end; uint64_t tries, last_send_us; } Message;

static Message send_buffer[4096];
static size_t send_buffer_count;
static uint32_t seq_local;

static struct
{
	bool idr_pending;
	uint8_t reported[0x10000]; // istemcinin bozuk bildirdiği kareler
	uint8_t received[1 << 20]; // güvenilir paket alındı mı (sıra numarasına göre)
	uint32_t cumulative;       // bu numaraya kadar hepsi alındı
	uint16_t frame, packet_index;
	uint16_t last_idr;
	bool sent_any;
} ps5;

static void send_buffer_ack(uint32_t cumulative)
{
	size_t kept = 0;
	for(size_t i = 0; i < send_buffer_count; i++)
		if(send_buffer[i].seq >= cumulative)
			send_buffer[kept++] = send_buffer[i];
	send_buffer_count = kept;
}

static void transmit(const Message *message)
{
	if(lost_at(now_us))
		return;
	if(message->seq < sizeof(ps5.received) && !ps5.received[message->seq])
	{
		ps5.received[message->seq] = 1;
		if(message->type == MSG_IDR)
			ps5.idr_pending = true;
		else if(message->type == MSG_CORRUPT && (uint16_t)(ps5.frame - message->start) < 512)
		{
			for(uint16_t f = message->start; ; f++)
			{
				ps5.reported[f] = 1;
				if(f == message->end || f == ps5.frame)
					break;
			}
			// bozuk kareye dayanan sonraki kareler de istemcide çözülemez: kodlayıcı onları da başvuru almaz
			for(uint16_t f = message->start; ; f++)
			{
				if(frame_kind[f] == KIND_P && ps5.reported[(uint16_t)(f - frame_reference[f] - 1)])
					ps5.reported[f] = 1;
				if(f == ps5.frame)
					break;
			}
		}
		while(ps5.cumulative < sizeof(ps5.received) && ps5.received[ps5.cumulative])
			ps5.cumulative++;
	}
	if(!lost_at(now_us + LINK_DELAY_US))
		send_buffer_ack(ps5.cumulative);
}

static void send_message(uint8_t type, uint16_t start, uint16_t end)
{
	Message message = { .seq = seq_local++, .type = type, .start = start, .end = end, .tries = 0, .last_send_us = now_us };
	if(send_buffer_count >= SEND_BUFFER_SIZE)
	{
		// takion.c paketi bir kez gönderir, tampon dolduğu için izlemez: kaybolursa yinelenmez
		stats.overflows++;
		transmit(&message);
		// PS5 bu numarayı hiç almazsa birikimli onay burada takılırdı; libchiaki 25 denemeden sonra vazgeçip sonraki
		// paketlere geçtiği için PS5'in de boşluğu atladığı varsayılır (iyimser taraf: yamasız kaynağın lehine)
		if(message.seq < sizeof(ps5.received))
			ps5.received[message.seq] = 1;
		return;
	}
	send_buffer[send_buffer_count++] = message;
	transmit(&message);
}

static void send_buffer_resend(void)
{
	for(size_t i = 0; i < send_buffer_count; i++)
	{
		Message *message = &send_buffer[i];
		if(now_us - message->last_send_us <= RESEND_TIMEOUT_US)
			continue;
		if(message->tries >= RESEND_TRIES_MAX)
		{
			stats.gave_up++;
			if(message->seq < sizeof(ps5.received))
				ps5.received[message->seq] = 1;
			uint32_t seq = message->seq;
			size_t kept = 0;
			for(size_t k = 0; k < send_buffer_count; k++)
				if(send_buffer[k].seq > seq)
					send_buffer[kept++] = send_buffer[k];
			send_buffer_count = kept;
			i = (size_t)-1;
			continue;
		}
		message->last_send_us = now_us;
		message->tries++;
		stats.resends++;
		transmit(message);
		// onay tamponu kaydırmış olabilir: baştan taranır (az önce gönderilenler süreleri dolmadığı için atlanır)
		i = (size_t)-1;
	}
}

ChiakiErrorCode stream_connection_send_corrupt_frame(ChiakiStreamConnection *stream_connection, ChiakiSeqNum16 start, ChiakiSeqNum16 end)
{
	(void)stream_connection;
	stats.corrupt_reports++;
	send_message(MSG_CORRUPT, start, end);
	return CHIAKI_ERR_SUCCESS;
}

ChiakiErrorCode stream_connection_send_idr_request(ChiakiStreamConnection *stream_connection)
{
	(void)stream_connection;
	stats.idr_requests++;
	send_message(MSG_IDR, 0, 0);
	return CHIAKI_ERR_SUCCESS;
}

// --- istemci: sıralama kuyruğu (takion.c'deki gibi) ve görüntü alıcısı ---

#define AV_REORDER_TIMEOUT_US 16000
#define VIDEO_QUEUE_SIZE_EXP 6

static ChiakiSession *session;
static ChiakiVideoReceiver *receiver;
static ChiakiReorderQueue queue;
static bool queue_initialized;
static int64_t head_wait_start_us;
static uint64_t head_wait_seq_num;
static uint64_t last_picture_us, connected_us, trouble_since_us;
static bool has_picture;

static bool video_sample(uint8_t *buf, size_t buf_size, int32_t frames_lost, bool frame_recovered, void *user)
{
	(void)frames_lost; (void)frame_recovered; (void)user;
	if(buf_size != sizeof(fp_out) || buf != fp_out)
		return true; // akış başlığı
	if(buf[0] == KIND_IDR)
		stats.idr_received++;
	uint64_t gap = now_us - last_picture_us;
	if(has_picture && gap > 250000)
	{
		stats.freezes++;
		stats.freeze_us_total += gap;
		if(gap > stats.freeze_us_max)
			stats.freeze_us_max = gap;
	}
	last_picture_us = now_us;
	has_picture = true;
	stats.pictures++;
	return true;
}

static void queue_drop(uint64_t seq_num, void *user, void *cb_user)
{
	(void)seq_num; (void)cb_user;
	stats.queue_drops++;
	free(user);
}

// takion.c: takion_av_queue_flush_with_timeout
static void queue_flush(void)
{
	int64_t now = (int64_t)now_us;
	bool made_progress = true;
	while(made_progress)
	{
		made_progress = false;
		uint64_t seq_num;
		ChiakiTakionAVPacket *packet;
		while(chiaki_reorder_queue_pull(&queue, &seq_num, (void **)&packet))
		{
			made_progress = true;
			chiaki_video_receiver_av_packet(receiver, packet);
			free(packet);
		}
		if(made_progress)
			head_wait_start_us = 0;
		if(chiaki_reorder_queue_count(&queue) == 0)
			break;
		if(head_wait_start_us != 0 && queue.begin != head_wait_seq_num)
		{
			if(queue.seq_num_gt(queue.begin, head_wait_seq_num))
				head_wait_seq_num = queue.begin;
			else
			{
				head_wait_start_us = now;
				head_wait_seq_num = queue.begin;
				break;
			}
		}
		if(head_wait_start_us == 0)
		{
			head_wait_start_us = now;
			head_wait_seq_num = queue.begin;
			break;
		}
		if(now - head_wait_start_us <= AV_REORDER_TIMEOUT_US)
			break;
		uint64_t skipped = 0;
		while(skipped < queue.count)
		{
			uint64_t seq_num_peek;
			void *entry_user;
			if(chiaki_reorder_queue_peek(&queue, skipped, &seq_num_peek, &entry_user))
				break;
			skipped++;
		}
		if(skipped >= queue.count)
			break;
		queue.begin = queue.seq_num_add(queue.begin, skipped);
		queue.count -= skipped;
		head_wait_start_us = 0;
		made_progress = true;
	}
}

static void receive(const ChiakiTakionAVPacket *sent)
{
	ChiakiTakionAVPacket *packet = malloc(sizeof(*packet));
	*packet = *sent;
	if(!queue_initialized)
	{
		ChiakiSeqNum16 begin = packet->packet_index;
		if(packet->unit_index > 0)
			begin = (ChiakiSeqNum16)(packet->packet_index - packet->unit_index);
		chiaki_reorder_queue_init_16(&queue, VIDEO_QUEUE_SIZE_EXP, begin);
		chiaki_reorder_queue_set_drop_strategy(&queue, CHIAKI_REORDER_QUEUE_DROP_STRATEGY_BEGIN);
		chiaki_reorder_queue_set_drop_cb(&queue, queue_drop, NULL);
		queue_initialized = true;
		head_wait_start_us = 0;
		head_wait_seq_num = begin;
	}
	chiaki_reorder_queue_push(&queue, packet->packet_index, packet);
	queue_flush();
}

// --- oturum ---

static uint16_t start_frame, start_packet;

static void session_open(void)
{
	session = calloc(1, sizeof(*session));
	receiver = calloc(1, sizeof(*receiver));
	session->connect_info.video_profile.codec = CHIAKI_CODEC_H264;
	session->connect_info.enable_idr_on_fec_failure = true;
	session->video_sample_cb = video_sample;
	chiaki_video_receiver_init(receiver, session, NULL);
	ChiakiVideoProfile profile = { .width = 1920, .height = 1080, .header_sz = 0, .header = NULL };
	chiaki_video_receiver_stream_info(receiver, &profile, 1);
	receiver->profiles_count = 1;

	memset(&ps5, 0, sizeof(ps5));
	ps5.frame = start_frame;
	ps5.packet_index = start_packet;
	ps5.idr_pending = true; // oturum anahtar kareyle başlar
	send_buffer_count = 0;
	seq_local = 0;
	queue_initialized = false;
	has_picture = false;
	connected_us = last_picture_us = now_us;
	trouble_since_us = 0;
}

static void session_close(void)
{
	if(queue_initialized)
		chiaki_reorder_queue_fini(&queue);
	// receiver->profiles[].header NULL; fini onu serbest bırakmaya çalışır (free(NULL) zararsız)
	chiaki_video_receiver_fini(receiver);
	free(receiver);
	free(session);
}

typedef struct { uint64_t arrive_us; ChiakiTakionAVPacket packet; } Arrival;
static int arrival_cmp(const void *a, const void *b)
{
	const Arrival *x = a, *y = b;
	return x->arrive_us < y->arrive_us ? -1 : x->arrive_us > y->arrive_us;
}

/** PS5 bir kare gönderir; ulaşan birimler varış sırasıyla istemciye verilir. */
static void ps5_send_frame(void)
{
	uint16_t f = ++ps5.frame;
	bool idr = ps5.idr_pending || !ps5.sent_any;
	uint8_t reference = 0;
	if(!idr)
	{
		// bozuk bildirilmemiş en yeni kareye başvur; son 16 karede yoksa IDR
		unsigned back = 0;
		for(; back < 16; back++)
		{
			uint16_t candidate = (uint16_t)(f - back - 1);
			if(!ps5.reported[candidate])
				break;
			if(candidate == ps5.last_idr)
			{
				back = 16;
				break;
			}
		}
		if(back >= 16)
			idr = true;
		else
			reference = (uint8_t)back;
	}
	if(idr)
	{
		ps5.idr_pending = false;
		ps5.last_idr = f;
		memset(ps5.reported, 0, sizeof(ps5.reported));
	}
	ps5.sent_any = true;
	frame_kind[f] = idr ? KIND_IDR : KIND_P;
	frame_reference[f] = reference;

	// 1080p30 ~15 Mbit/sn: P karesi ~40 birim, IDR ~5 katı; FEC kaynağın 1/8'i
	unsigned source = idr ? 200 : 40;
	unsigned fec = source / 8;
	static Arrival arrivals[512];
	size_t count = 0;
	for(unsigned unit = 0; unit < source + fec; unit++)
	{
		uint64_t sent_us = now_us + unit * 60; // birimler ~60 µs arayla çıkar
		uint16_t index = ps5.packet_index++;
		stats.units_sent++;
		if(lost_at(sent_us))
		{
			stats.units_lost++;
			continue;
		}
		Arrival *arrival = &arrivals[count++];
		arrival->arrive_us = sent_us + LINK_DELAY_US + (rnd() < scenario->reorder ? (uint64_t)(rnd() * 600) : 0);
		memset(&arrival->packet, 0, sizeof(arrival->packet));
		arrival->packet.packet_index = index;
		arrival->packet.frame_index = f;
		arrival->packet.is_video = true;
		arrival->packet.unit_index = (ChiakiSeqNum16)unit;
		arrival->packet.units_in_frame_total = (uint16_t)(source + fec);
		arrival->packet.units_in_frame_fec = (uint16_t)fec;
		arrival->packet.data_size = 1;
	}
	qsort(arrivals, count, sizeof(Arrival), arrival_cmp);
	for(size_t i = 0; i < count; i++)
	{
		if(arrivals[i].arrive_us > now_us)
			now_us = arrivals[i].arrive_us;
		receive(&arrivals[i].packet);
	}
}

// --- uygulama: görüntü bekçisi ve yeniden bağlanma aralıkları (StreamSession) ---

#ifdef APP_NEW
#define WATCHDOG_US 15000000ULL
#else
#define WATCHDOG_US 8000000ULL
#endif

static int attempt;

static unsigned reconnect_delay_s(uint64_t session_us)
{
#ifdef APP_NEW
	if(session_us >= 300 * 1000000ULL) attempt = 0;
	if(attempt < 2) attempt = 2;
	unsigned delay = 2u << attempt;
	if(delay > 60) delay = 60;
	if(attempt < 5) attempt++;
	return delay;
#else
	if(session_us >= 60 * 1000000ULL) attempt = 0;
	unsigned delay = 2u << attempt;
	if(delay > 30) delay = 30;
	if(attempt < 4) attempt++;
	return delay;
#endif
}

#define FRAME_US 33333
#define CONNECT_US 3000000ULL // yeni oturumun kurulması

static void run(const Scenario *s, uint64_t seed, double minutes)
{
	scenario = s;
	rng_state = seed * 0x9E3779B97F4A7C15ULL + 1;
	now_us = 1000000;
	burst_end_us = 0;
	burst_schedule(now_us);
	attempt = 0;
	// kare ve paket numaraları 16 bit sınırının hemen önünden başlar: sarma her koşuda sınanır
	start_frame = 0xff00;
	start_packet = 0xf000;
	session_open();
	uint64_t end_us = now_us + (uint64_t)(minutes * 60e6);
	uint64_t next_resend_us = now_us, next_heartbeat_us = now_us;
	while(now_us < end_us)
	{
		uint64_t frame_end = now_us + FRAME_US;
		ps5_send_frame();
		// kareler arasında: kuyruk süre aşımı, yeniden gönderme, kalp atışı
		for(uint64_t t = now_us + 4000; t < frame_end; t += 4000)
		{
			now_us = t;
			if(queue_initialized)
				queue_flush();
			if(now_us >= next_resend_us)
			{
				send_buffer_resend();
				next_resend_us = now_us + RESEND_WAKEUP_US;
			}
			if(now_us >= next_heartbeat_us)
			{
				send_message(MSG_HEARTBEAT, 0, 0);
				next_heartbeat_us = now_us + 1000000;
			}
		}
		now_us = frame_end;

		// toparlanma süresi: IDR beklemeye girilmesinden yeniden görüntü gelene kadar
		bool waiting = chiaki_video_receiver_get_waiting_for_idr(receiver);
		if(waiting && !trouble_since_us)
			trouble_since_us = now_us;
		else if(!waiting && trouble_since_us)
		{
			uint64_t took = now_us - trouble_since_us;
			stats.recover_count++;
			stats.recover_us_total += took;
			if(took > stats.recover_us_max)
				stats.recover_us_max = took;
			trouble_since_us = 0;
		}

		if(now_us - last_picture_us >= WATCHDOG_US)
		{
			stats.watchdog_drops++;
			uint64_t session_us = now_us - connected_us;
			start_frame = ps5.frame;
			start_packet = ps5.packet_index;
			session_close();
			uint64_t down = reconnect_delay_s(session_us) * 1000000ULL + CONNECT_US;
			stats.down_us += down + WATCHDOG_US;
			now_us += down;
			session_open();
			next_resend_us = next_heartbeat_us = now_us;
		}
	}
	session_close();
}

int main(int argc, char **argv)
{
	static const Scenario scenarios[] = {
		{ "kayip %1", 0.01, 0, 0, 0, 0.002 },
		{ "kayip %3", 0.03, 0, 0, 0, 0.002 },
		{ "kayip %5", 0.05, 0, 0, 0, 0.002 },
		{ "patlama: 10 sn'de bir ~80 ms %60", 0.002, 10, 0.08, 0.6, 0.002 },
		{ "patlama: 30 sn'de bir ~400 ms %100", 0.005, 30, 0.4, 1.0, 0.002 },
		{ "patlama: 60 sn'de bir ~1,5 sn %90 + %2", 0.02, 60, 1.5, 0.9, 0.002 },
		{ "kotu ag: %4 + 20 sn'de bir ~600 ms %80", 0.04, 20, 0.6, 0.8, 0.01 },
		{ "temiz ag, yalniz sira bozulmasi %5", 0.0, 0, 0, 0, 0.05 },
	};
	double minutes = 60;
	int seeds = 5;
	int only = -1;
	int check = 0, failed = 0;
	for(int i = 1; i < argc; i++)
	{
		if(!strcmp(argv[i], "-v")) verbose = 1;
		else if(!strcmp(argv[i], "-c")) check = 1;
		else if(!strcmp(argv[i], "-m") && i + 1 < argc) minutes = atof(argv[++i]);
		else if(!strcmp(argv[i], "-n") && i + 1 < argc) seeds = atoi(argv[++i]);
		else if(!strcmp(argv[i], "-s") && i + 1 < argc) only = atoi(argv[++i]);
	}
	printf("# %s: gonderme tamponu %d, bekci %d sn, senaryo basina %d x %.0f dk\n", VARIANT, SEND_BUFFER_SIZE,
		(int)(WATCHDOG_US / 1000000), seeds, minutes);
	printf("%-40s %8s %8s %8s %8s %8s %9s %9s %8s %9s %8s %8s %8s\n", "senaryo", "FEC-hata", "IDR-ist", "IDR-gel", "bozuk-b",
		"tasma", "topar-ort", "topar-enb", "donma", "donma-enb", "kopma", "goruntu%", "kuyr-at");
	for(size_t i = 0; i < sizeof(scenarios) / sizeof(scenarios[0]); i++)
	{
		if(only >= 0 && (size_t)only != i)
			continue;
		memset(&stats, 0, sizeof(stats));
		for(int seed = 1; seed <= seeds; seed++)
			run(&scenarios[i], (uint64_t)seed, minutes);
		double total_s = seeds * minutes * 60;
		double hours = total_s / 3600;
		double frozen_s = (stats.freeze_us_total + stats.down_us) / 1e6;
		printf("%-40s %8.0f %8.0f %8.0f %8.0f %8.0f %8.2fs %8.2fs %8.0f %8.2fs %8.1f %7.2f%% %8.0f\n", scenarios[i].name,
			stats.fec_failures / hours, stats.idr_requests / hours, stats.idr_received / hours, stats.corrupt_reports / hours,
			stats.overflows / hours,
			stats.recover_count ? stats.recover_us_total / 1e6 / stats.recover_count : 0, stats.recover_us_max / 1e6,
			stats.freezes / hours, stats.freeze_us_max / 1e6, stats.watchdog_drops / hours,
			100.0 * (1.0 - frozen_s / total_s), stats.queue_drops / hours);
		// -c: yamalı kaynakta kayıp tek başına oturumu düşürmemeli; kayıpsız ağda sırası bozulan paket atılmamalı
		if(check && stats.watchdog_drops)
		{
			printf("HATA: \"%s\" senaryosunda goruntu bekcisi oturumu %llu kez kapatti\n", scenarios[i].name, (unsigned long long)stats.watchdog_drops);
			failed = 1;
		}
		if(check && scenarios[i].loss == 0 && scenarios[i].burst_every_s == 0 && (stats.queue_drops || stats.fec_failures))
		{
			printf("HATA: kayipsiz agda %llu paket atildi, %llu karede FEC tutmadi\n", (unsigned long long)stats.queue_drops, (unsigned long long)stats.fec_failures);
			failed = 1;
		}
	}
	return failed;
}
