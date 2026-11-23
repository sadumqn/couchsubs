// SPDX-License-Identifier: AGPL-3.0-only

using CouchSubs.Core;

namespace CouchSubs.Core.Tests;

public class PaddleOcrTests
{
    [Fact]
    public void Characters_come_from_the_yaml_dictionary_with_blank_first_and_space_last()
    {
        var yaml = "Global:\n  model_name: x\nPostProcess:\n  name: CTCLabelDecode\n  character_dict:\n  - '!'\n  - ''''\n  - a\n  - 中\n  - '-'\nPreProcess:\n  x: 1\n";
        var characters = PaddleOcr.ParseCharacters(yaml);
        Assert.Equal(["", "!", "'", "a", "中", "-", " "], characters);
    }

    [Fact]
    public void Characters_are_read_from_crlf_yaml_too() =>
        Assert.Equal(["", "a", "b", " "], PaddleOcr.ParseCharacters("PostProcess:\r\n  character_dict:\r\n  - a\r\n  - b\r\n"));

    [Fact]
    public void Missing_dictionary_is_an_error() =>
        Assert.Throws<InvalidDataException>(() => PaddleOcr.ParseCharacters("PostProcess:\n  name: CTCLabelDecode\n"));

    [Fact]
    public void Decoding_drops_repeats_and_blanks_and_averages_the_kept_probabilities()
    {
        string[] characters = ["", "h", "i", " "];
        // Adımlar h h blank i i blank i: art arda aynı sınıf bir kez sayılır, araya blank girince yeniden sayılır → "hii".
        float[][] steps =
        [
            [0.1f, 0.8f, 0.05f, 0.05f],
            [0.1f, 0.6f, 0.2f, 0.1f],
            [0.9f, 0.05f, 0.03f, 0.02f],
            [0.1f, 0.1f, 0.7f, 0.1f],
            [0.1f, 0.1f, 0.75f, 0.05f],
            [0.95f, 0.02f, 0.02f, 0.01f],
            [0.1f, 0.1f, 0.6f, 0.2f],
        ];
        var (text, confidence) = PaddleOcr.Decode(steps.SelectMany(s => s).ToArray(), steps.Length, characters);
        Assert.Equal("hii", text);
        Assert.Equal((0.8 + 0.7 + 0.6) / 3, confidence, 5);
    }

    [Fact]
    public void Decoding_only_blanks_gives_nothing()
    {
        var (text, confidence) = PaddleOcr.Decode(new float[] { 0.9f, 0.1f, 0.8f, 0.2f }, 2, ["", "a"]);
        Assert.Equal("", text);
        Assert.Equal(0, confidence);
    }

    [Fact]
    public void Detection_input_is_a_multiple_of_32_and_within_the_limit()
    {
        var input = PaddleOcr.PrepareDetection(Solid(1382, 378, 255), 960);
        Assert.Equal(960, input.Width);
        Assert.Equal(256, input.Height);
        Assert.Equal(3 * input.Width * input.Height, input.Data.Length);
        // Beyaz piksel: (1 − ortalama) / sapma, BGR sırasıyla.
        Assert.Equal((1 - 0.485f) / 0.229f, input.Data[0], 4);
        Assert.Equal((1 - 0.406f) / 0.225f, input.Data[2 * input.Width * input.Height], 4);
    }

    [Fact]
    public void Small_images_are_not_enlarged_for_detection()
    {
        var input = PaddleOcr.PrepareDetection(Solid(922, 252, 0), 960);
        Assert.Equal(928, input.Width);
        Assert.Equal(256, input.Height);
    }

    [Fact]
    public void Large_images_get_the_larger_detection_limit()
    {
        Assert.Equal(PaddleOcr.DetectionLimit, PaddleOcr.DetectionLimitFor(922, 252));
        Assert.Equal(PaddleOcr.LargeDetectionLimit, PaddleOcr.DetectionLimitFor(1920, 1080));
    }

    [Fact]
    public void Boxes_are_found_widened_scaled_and_sorted()
    {
        const int w = 200, h = 100;
        var map = new float[w * h];
        Fill(map, w, 120, 60, 180, 70, 0.9f); // alt satır
        Fill(map, w, 20, 20, 100, 30, 0.9f);  // üst satır
        var boxes = PaddleOcr.FindBoxes(map, w, h, 400, 200);
        Assert.Equal(2, boxes.Count);
        Assert.True(boxes[0].Top < boxes[1].Top);
        // Üst satır: 20..99 × 20..29 piksel, 2×2 genişletmeyle 20..100 × 20..30; kutu 80 × 10, dışa 80·10·1,6 / 180 ≈ 7,1 piksel.
        var top = boxes[0];
        Assert.Equal(Math.Round((20 - 80 * 10 * 1.6 / 180) * 2), top.Left);
        Assert.Equal(Math.Round((100 + 80 * 10 * 1.6 / 180) * 2), top.Right);
        Assert.True(top.Top < 40 && top.Bottom > 60);
    }

    [Fact]
    public void Faint_and_tiny_spots_are_not_boxes()
    {
        const int w = 100, h = 50;
        var map = new float[w * h];
        Fill(map, w, 10, 10, 60, 20, 0.35f); // eşiği geçer ama kutu ortalaması 0,5'in altında
        Fill(map, w, 80, 30, 82, 32, 0.95f); // 2 piksellik leke
        Assert.Empty(PaddleOcr.FindBoxes(map, w, h, w, h));
    }

    [Fact]
    public void Boxes_on_the_same_line_go_left_to_right_even_if_a_little_higher()
    {
        const int w = 300, h = 60;
        var map = new float[w * h];
        Fill(map, w, 200, 20, 280, 34, 0.9f);
        Fill(map, w, 20, 24, 150, 38, 0.9f);
        var boxes = PaddleOcr.FindBoxes(map, w, h, w, h);
        Assert.Equal(2, boxes.Count);
        Assert.True(boxes[0].Left < boxes[1].Left);
    }

    [Fact]
    public void Recognition_input_is_48_high_at_least_320_wide_and_padded_with_zero()
    {
        var (data, width) = PaddleOcr.PrepareRecognition([Solid(100, 48, 255)]);
        Assert.Equal(320, width);
        Assert.Equal(3 * 48 * 320, data.Length);
        Assert.Equal(1f, data[0]);           // beyaz: (1 − 0,5) / 0,5
        Assert.Equal(0f, data[319]);         // dolgu
    }

    [Fact]
    public void Recognition_width_follows_the_widest_line_of_the_batch()
    {
        var (data, width) = PaddleOcr.PrepareRecognition([Solid(100, 20, 0), Solid(400, 20, 0)]);
        Assert.Equal(960, width);
        Assert.Equal(2 * 3 * 48 * 960, data.Length);
        Assert.Equal(-1f, data[0]);          // siyah: (0 − 0,5) / 0,5
        Assert.Equal(0f, data[240]);         // ilk satır 240 piksel genişliğinde, ötesi dolgu
    }

    [Fact]
    public void Crop_keeps_the_box()
    {
        var crop = PaddleOcr.CropBox(Solid(100, 50, 10), new PaddleOcr.Box(10.4, 5, 60.9, 25));
        Assert.Equal(50, crop.Width);
        Assert.Equal(20, crop.Height);
    }

    [Fact]
    public void Cjk_characters_are_dropped_for_latin_languages()
    {
        Assert.Equal("", PaddleOcr.LatinOnly("一 0"));
        Assert.Equal("Get in the car", PaddleOcr.LatinOnly("Get 中 in the car"));
        Assert.Equal("Çok güzel, değil mi?", PaddleOcr.LatinOnly("Çok güzel, değil mi?"));
        Assert.True(PaddleOcr.IsLatinLanguage("en-US"));
        Assert.True(PaddleOcr.IsLatinLanguage("tr"));
        Assert.False(PaddleOcr.IsLatinLanguage("ja"));
    }

    [Fact]
    public void Model_files_are_pinned_with_hashes()
    {
        Assert.Equal(3, PaddleOcr.Files.Count);
        Assert.All(PaddleOcr.Files, file =>
        {
            Assert.Equal(64, file.Sha256.Length);
            Assert.Contains("/resolve/", file.Url.AbsoluteUri);
            Assert.DoesNotContain("/resolve/main/", file.Url.AbsoluteUri);
            Assert.True(file.Bytes > 0);
        });
    }

    private static Frame Solid(int width, int height, byte value)
    {
        var frame = Frame.Blank(width, height);
        for (var i = 0; i < frame.Pixels.Length; i += 4)
        {
            frame.Pixels[i] = frame.Pixels[i + 1] = frame.Pixels[i + 2] = value;
            frame.Pixels[i + 3] = 255;
        }
        return frame;
    }

    private static void Fill(float[] map, int width, int x0, int y0, int x1, int y1, float value)
    {
        for (var y = y0; y < y1; y++)
            for (var x = x0; x < x1; x++)
                map[(y * width) + x] = value;
    }
}
