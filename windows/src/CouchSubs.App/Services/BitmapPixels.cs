// SPDX-License-Identifier: AGPL-3.0-only

using System.Runtime.InteropServices;
using CouchSubs.Core;
using Windows.Graphics.Imaging;
using WinRT;

namespace CouchSubs.App.Services;

/// <summary>
/// Windows görüntüsü (<see cref="SoftwareBitmap"/>) ile yönetilen kare dizisi arasında piksel kopyası. Görüntünün belleği
/// kilitlenir ve satırlar bizim kodumuzla, iki yanın boyu denetlenerek kopyalanır.
///
/// Eskiden <c>bitmap.CopyToBuffer(pixels.AsBuffer())</c> ve <c>CopyFromBuffer</c> kullanılıyordu: yerel kod yönetilen
/// dizinin içine doğrudan yazıyor, dizi de sarmalayıcısı sonlandırılana (finalizer) kadar bellekte sabitlenmiş (pinned)
/// kalıyordu. 1440p pencere yakalamada saniyede on tane 14 MB'lık dizi ve her okumada birkaç dizi böyle sabitleniyordu.
/// Uzun oturumdaki erişim ihlalinin (GitHub #587) nedeni kesinleşmedi; yönetilen belleğe yerel yazma ve sonlandırıcıya
/// bağlı sabitleme bu yoldan kaldırıldı.
/// </summary>
internal static unsafe class BitmapPixels
{
    [ComImport, Guid("5B0D3235-4DBA-4D44-865E-8F1D0E4FD04D"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMemoryBufferByteAccess
    {
        void GetBuffer(out byte* buffer, out uint capacity);
    }

    /// <summary>BGRA8 görüntünün pikselleri, satır başına tam <c>genişlik × 4</c> bayt (dolgusuz) yeni bir dizide.</summary>
    public static Frame Read(SoftwareBitmap bitmap)
    {
        using var buffer = bitmap.LockBuffer(BitmapBufferAccessMode.Read);
        using var reference = buffer.CreateReference();
        var plane = buffer.GetPlaneDescription(0);
        reference.As<IMemoryBufferByteAccess>().GetBuffer(out var data, out var capacity);
        var (width, height) = (plane.Width, plane.Height);
        var row = Check(plane, capacity, data);
        var pixels = new byte[row * height];
        fixed (byte* target = pixels)
            for (var y = 0; y < height; y++)
                Buffer.MemoryCopy(data + plane.StartIndex + ((long)y * plane.Stride), target + ((long)y * row), row, row);
        return new Frame(pixels, width, height, row);
    }

    /// <summary>Kareyi aynı boydaki BGRA8 görüntüye yazar.</summary>
    public static void Write(Frame image, SoftwareBitmap bitmap)
    {
        using var buffer = bitmap.LockBuffer(BitmapBufferAccessMode.Write);
        using var reference = buffer.CreateReference();
        var plane = buffer.GetPlaneDescription(0);
        reference.As<IMemoryBufferByteAccess>().GetBuffer(out var data, out var capacity);
        var row = Check(plane, capacity, data);
        if (plane.Width != image.Width || plane.Height != image.Height || image.Stride < row
            || image.Pixels.LongLength < ((long)(image.Height - 1) * image.Stride) + row)
            throw new ArgumentException($"frame {image.Width}x{image.Height} (stride {image.Stride}, {image.Pixels.Length} bytes) does not fit bitmap {plane.Width}x{plane.Height}");
        fixed (byte* source = image.Pixels)
            for (var y = 0; y < image.Height; y++)
                Buffer.MemoryCopy(source + ((long)y * image.Stride), data + plane.StartIndex + ((long)y * plane.Stride), row, row);
    }

    /// <summary>Görüntünün belleği anlatılan düzene yetiyor mu; satırın bayt sayısını döndürür.</summary>
    private static int Check(BitmapPlaneDescription plane, uint capacity, byte* data)
    {
        var row = checked(plane.Width * 4);
        if (data == null || plane.Width <= 0 || plane.Height <= 0 || plane.StartIndex < 0 || plane.Stride < row
            || plane.StartIndex + ((long)(plane.Height - 1) * plane.Stride) + row > capacity)
            throw new InvalidOperationException($"unexpected bitmap layout: {plane.Width}x{plane.Height}, stride {plane.Stride}, start {plane.StartIndex}, capacity {capacity}");
        return row;
    }
}
