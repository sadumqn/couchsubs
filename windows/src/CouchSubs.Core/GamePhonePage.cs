// SPDX-License-Identifier: AGPL-3.0-only

namespace CouchSubs.Core;

/// <summary>Bir sonraki telefon okumasından ve bekleyen çeviriyi göstermeden önce yalnız yazı kutularını sınar.</summary>
internal sealed class GamePhonePage
{
    private readonly (TextBox Box, int Columns, int Rows, byte[] Samples)[] patches;

    public GamePhonePage(Frame frame, CropRegion region, Reading reading)
    {
        TextBox[] boxes = [.. reading.Lines.Where(line => line.Box.HasValue).Select(line => line.Box!.Value)];
        if (boxes.Length == 0) boxes = [new TextBox(0, 0, 1, 1)];
        patches = [.. boxes.Select(box =>
        {
            int columns = Math.Clamp((int)Math.Ceiling((box.Right - box.Left) * (region.Right - region.Left) * frame.Width), 1, 128);
            int rows = Math.Clamp((int)Math.Ceiling((box.Bottom - box.Top) * (region.Bottom - region.Top) * frame.Height), 1, 12);
            return (box, columns, rows, new byte[columns * rows]);
        })];
        Sample(frame, region, compare: false);
    }

    public bool Changed(Frame frame, CropRegion region) => Sample(frame, region, compare: true);

    private bool Sample(Frame frame, CropRegion region, bool compare)
    {
        var place = new TextBox(region.Left, region.Top, region.Right, region.Bottom);
        foreach (var (relative, columns, rows, samples) in patches)
        {
            int index = 0;
            int firstChangedPixel = -1;
            var box = relative.PlacedIn(place);
            for (var row = 0; row < rows; row++)
            {
                int y = Math.Clamp((int)((box.Top + (row + .5) * (box.Bottom - box.Top) / rows) * frame.Height), 0, frame.Height - 1);
                for (var column = 0; column < columns; column++, index++)
                {
                    int x = Math.Clamp((int)((box.Left + (column + .5) * (box.Right - box.Left) / columns) * frame.Width), 0, frame.Width - 1);
                    int p = y * frame.Stride + x * 4;
                    byte value = (byte)((frame.Pixels[p] + frame.Pixels[p + 1] * 2 + frame.Pixels[p + 2]) / 4);
                    if (!compare) samples[index] = value;
                    else if (Math.Abs(samples[index] - value) > ReadScheduler.ChangeThreshold)
                    {
                        // Tek bir pikseldeki kodlama paraziti yeni harf sayılmaz.
                        if (firstChangedPixel >= 0 && firstChangedPixel != p) return true;
                        firstChangedPixel = p;
                    }
                }
            }
        }
        return false;
    }
}
