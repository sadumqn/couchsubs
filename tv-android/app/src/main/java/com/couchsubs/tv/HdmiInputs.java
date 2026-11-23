// SPDX-License-Identifier: AGPL-3.0-only
package com.couchsubs.tv;

import android.content.Context;
import android.content.SharedPreferences;
import android.media.tv.TvInputInfo;
import android.media.tv.TvInputManager;

import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;

/** TV'nin HDMI girişleri; uygulama içi mod ve katman modu ortak kullanır. */
final class HdmiInputs {
    private static final String PREFS = "couchsubs";
    /** En son görüntü gelen ya da kullanıcının seçtiği girişin kimliği. */
    private static final String KEY_LAST_INPUT = "lastHdmiInput";

    private HdmiInputs() {}

    /**
     * TV'nin HDMI girişleri, port numarasına göre sıralı. Girişin numarası sıradaki yeridir.
     * HDMI-CEC ile bağlı cihazlar (PS5 gibi) bazı TV'lerde girişin "alt girişi" olarak ayrıca listelenir; onlar sayılmaz,
     * yoksa numaralar kayar ve iki bağlı giriş görünür. Kimlikler sayısal sıralanır ("HW10", "HW2"den sonra gelir).
     */
    static List<TvInputInfo> list(Context context) {
        List<TvInputInfo> inputs = new ArrayList<>();
        TvInputManager manager = manager(context);
        if (manager == null) return inputs;
        for (TvInputInfo input : manager.getTvInputList()) {
            if (input.getType() == TvInputInfo.TYPE_HDMI && input.isPassthroughInput() && input.getParentId() == null) {
                inputs.add(input);
            }
        }
        Collections.sort(inputs, (first, second) -> {
            int order = Long.compare(lastNumber(first.getId()), lastNumber(second.getId()));
            return order != 0 ? order : first.getId().compareTo(second.getId());
        });
        return inputs;
    }

    /** 1'den başlayan numaraya karşılık gelen HDMI girişinin kimliği, yoksa null. */
    static String idForPort(Context context, int port) {
        List<TvInputInfo> inputs = list(context);
        return port >= 1 && port <= inputs.size() ? inputs.get(port - 1).getId() : null;
    }

    /**
     * Giriş seçicide bir satır: numara, kimlik, CEC'in bildirdiği cihaz adı (ör. "PS5"; yoksa null), cihaz bağlı mı,
     * TV girişin boş olduğunu açıkça bildiriyor mu.
     */
    static final class Choice {
        final int port;
        final String id;
        final String device;
        final boolean connected;
        final boolean disconnected;

        Choice(int port, String id, String device, boolean connected, boolean disconnected) {
            this.port = port;
            this.id = id;
            this.device = device;
            this.connected = connected;
            this.disconnected = disconnected;
        }
    }

    /** Giriş seçici için TV'nin HDMI girişleri. Liste boşsa TV HDMI girişlerini uygulamalara açmıyordur. */
    static List<Choice> choices(Context context) {
        List<Choice> choices = new ArrayList<>();
        TvInputManager manager = manager(context);
        if (manager == null) return choices;
        List<TvInputInfo> inputs = list(context);
        for (int i = 0; i < inputs.size(); i++) {
            String id = inputs.get(i).getId();
            int state;
            try {
                state = manager.getInputState(id);
            } catch (RuntimeException e) {
                state = -1;
            }
            choices.add(new Choice(i + 1, id, deviceName(context, manager, id),
                    state == TvInputManager.INPUT_STATE_CONNECTED, state == TvInputManager.INPUT_STATE_DISCONNECTED));
        }
        return choices;
    }

    /** Açılışta açılacak giriş ve neden seçildiği; port 0 ise bilinmiyor, kullanıcıya giriş seçici gösterilir. */
    static final class Pick {
        static final String CONSOLE = "console";
        static final String SAVED = "saved";
        static final String LAST = "last";
        static final String ACTIVE = "active";

        final int port;
        final String reason;

        Pick(int port, String reason) {
            this.port = port;
            this.reason = reason;
        }
    }

    private static final Pick NONE = new Pick(0, null);

    /**
     * Konsolun girişini seçer (#367, #360). Eskiden bulunamayınca sessizce HDMI 1 açılıyordu: PS5 HDMI 3'teyken ve
     * HDMI-CEC kapalıyken TV HDMI 1'e geçiyordu. Sıra:
     * 1. HDMI-CEC'in bildirdiği cihaz adı PS5 ya da Xbox olan giriş (en kesin bilgi),
     * 2. kullanıcının seçtiği giriş (sayı tuşu ya da giriş seçici),
     * 3. en son görüntü gelen ya da seçilen giriş (TV o girişin boş olduğunu açıkça bildirmiyorsa),
     * 4. tek bağlı (sinyal veren) HDMI girişi.
     * Hiçbiri yoksa 0: hiçbir giriş açılmaz, kullanıcı seçer. Listede olmayan numara yok sayılır.
     */
    static Pick pick(List<Choice> inputs, int saved, int last) {
        for (Choice input : inputs) {
            if (looksLikeConsole(input.device)) return new Pick(input.port, Pick.CONSOLE);
        }
        Choice chosen = find(inputs, saved);
        if (chosen != null) return new Pick(chosen.port, Pick.SAVED);
        Choice previous = find(inputs, last);
        if (previous != null && !previous.disconnected) return new Pick(previous.port, Pick.LAST);
        Choice active = null;
        for (Choice input : inputs) {
            if (!input.connected) continue;
            if (active != null) return NONE;
            active = input;
        }
        return active != null ? new Pick(active.port, Pick.ACTIVE) : NONE;
    }

    private static Choice find(List<Choice> inputs, int port) {
        if (port <= 0) return null;
        for (Choice input : inputs) {
            if (input.port == port) return input;
        }
        return null;
    }

    /** {@link #pick} bu TV'nin girişleriyle; saved sayfanın kaydettiği numara (yoksa 0), son giriş uygulamanın kaydı. */
    static Pick pick(Context context, int saved) {
        List<Choice> inputs = choices(context);
        String lastId = prefs(context).getString(KEY_LAST_INPUT, null);
        int last = 0;
        for (Choice input : inputs) {
            if (input.id.equals(lastId)) last = input.port;
        }
        return pick(inputs, saved, last);
    }

    /** Görüntü gelen ya da kullanıcının seçtiği giriş; sonraki açılışlarda da bu açılır. */
    static void remember(Context context, String id) {
        if (id != null) prefs(context).edit().putString(KEY_LAST_INPUT, id).apply();
    }

    /** Kullanıcı "0" ile seçimi bıraktı: kayıtlı giriş unutulur, konsol yeniden aranır. */
    static void forget(Context context) {
        prefs(context).edit().remove(KEY_LAST_INPUT).apply();
    }

    /** PS5'in ya da Xbox'ın girişi (CEC adı ya da tek bağlı giriş), bulunamazsa 0. */
    static int consolePort(Context context) {
        return pick(choices(context), 0, 0).port;
    }

    /** Girişte bir cihaz var mı; TV bunu bildirmiyorsa var sayılır. */
    static boolean hasSource(Context context, String id) {
        TvInputManager manager = manager(context);
        if (manager == null || id == null) return true;
        try {
            return manager.getInputState(id) != TvInputManager.INPUT_STATE_DISCONNECTED;
        } catch (RuntimeException e) {
            return true;
        }
    }

    /** Girişin altında HDMI-CEC ile görünen cihazın adı (alt girişin etiketi), yoksa null. */
    private static String deviceName(Context context, TvInputManager manager, String parentId) {
        try {
            for (TvInputInfo input : manager.getTvInputList()) {
                if (!parentId.equals(input.getParentId())) continue;
                CharSequence label = input.loadLabel(context);
                if (label != null && label.toString().trim().length() > 0) return label.toString().trim();
            }
        } catch (RuntimeException ignored) {
        }
        return null;
    }

    /** CEC cihaz adı bir PlayStation ya da Xbox mı ("PS5", "PlayStation 5", "SONY PS5", "Xbox Series X"). */
    static boolean looksLikeConsole(String name) {
        if (name == null) return false;
        String plain = name.toLowerCase(Locale.ROOT).replace(" ", "");
        return plain.contains("ps5") || plain.contains("playstation") || plain.contains("xbox");
    }

    private static SharedPreferences prefs(Context context) {
        return context.getSharedPreferences(PREFS, Context.MODE_PRIVATE);
    }

    private static TvInputManager manager(Context context) {
        return (TvInputManager) context.getSystemService(Context.TV_INPUT_SERVICE);
    }

    /** Kimliğin sonundaki sayı ("…/HW15" → 15); yoksa en sona konur. */
    static long lastNumber(String id) {
        int end = id.length();
        while (end > 0 && !Character.isDigit(id.charAt(end - 1))) end--;
        int start = end;
        while (start > 0 && Character.isDigit(id.charAt(start - 1))) start--;
        if (start == end) return Long.MAX_VALUE;
        try { return Long.parseLong(id.substring(start, end)); } catch (NumberFormatException e) { return Long.MAX_VALUE; }
    }
}
