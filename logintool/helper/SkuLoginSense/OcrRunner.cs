using System;
using System.Collections.Generic;
using System.Drawing;
using System.IO;
using Windows.Globalization;
using Windows.Graphics.Imaging;
using Windows.Media.Ocr;
using Windows.Storage.Streams;

namespace SkuLoginSense
{
    public sealed class OcrLine
    {
        public string Text;
        public int X, Y, W, H;
    }

    /// <summary>
    /// Windows.Media.Ocr over a GDI bitmap - onboard, offline, no cloud
    /// (hard rule). Same engine the font probe validated against the live
    /// 2.5.5 client at 2880x1800 and against the bundled screenshots.
    /// </summary>
    public static class OcrRunner
    {
        static string _cachedRequest;
        static OcrEngine _cachedEngine;

        public static string ResolveLanguage(string requested, out OcrEngine engine)
        {
            if (_cachedEngine != null && _cachedRequest == requested)
            {
                engine = _cachedEngine;
                return engine.RecognizerLanguage?.LanguageTag;
            }
            engine = null;
            if (!string.IsNullOrEmpty(requested))
            {
                try { engine = OcrEngine.TryCreateFromLanguage(new Language(requested)); }
                catch { }
            }
            if (engine == null) engine = OcrEngine.TryCreateFromUserProfileLanguages();
            _cachedRequest = requested;
            _cachedEngine = engine;
            return engine?.RecognizerLanguage?.LanguageTag;
        }

        public static List<OcrLine> Recognize(Bitmap bmp, OcrEngine engine, Rectangle? region)
        {
            Bitmap target = bmp;
            int dx = 0, dy = 0;
            if (region.HasValue)
            {
                var r = Rectangle.Intersect(region.Value, new Rectangle(0, 0, bmp.Width, bmp.Height));
                if (r.Width <= 0 || r.Height <= 0) return new List<OcrLine>();
                target = bmp.Clone(r, bmp.PixelFormat);
                dx = r.X; dy = r.Y;
            }

            try
            {
                SoftwareBitmap sb = ToSoftwareBitmap(target);
                using (sb)
                {
                    var result = engine.RecognizeAsync(sb).AsTask().GetAwaiter().GetResult();
                    var lines = new List<OcrLine>();
                    foreach (var line in result.Lines)
                    {
                        double minX = double.MaxValue, minY = double.MaxValue, maxX = 0, maxY = 0;
                        foreach (var w in line.Words)
                        {
                            var r = w.BoundingRect;
                            if (r.X < minX) minX = r.X;
                            if (r.Y < minY) minY = r.Y;
                            if (r.X + r.Width > maxX) maxX = r.X + r.Width;
                            if (r.Y + r.Height > maxY) maxY = r.Y + r.Height;
                        }
                        lines.Add(new OcrLine
                        {
                            Text = line.Text,
                            X = (int)minX + dx,
                            Y = (int)minY + dy,
                            W = (int)(maxX - minX),
                            H = (int)(maxY - minY),
                        });
                    }
                    return lines;
                }
            }
            finally
            {
                if (!ReferenceEquals(target, bmp)) target.Dispose();
            }
        }

        static SoftwareBitmap ToSoftwareBitmap(Bitmap bmp)
        {
            // Round-trip through an in-memory PNG: simple, lossless, and fast
            // enough for one-shot sensing.
            using (var ms = new MemoryStream())
            {
                bmp.Save(ms, System.Drawing.Imaging.ImageFormat.Png);
                ms.Position = 0;
                using (var ras = new InMemoryRandomAccessStream())
                {
                    var writer = ras.AsStreamForWrite();
                    ms.CopyTo(writer);
                    writer.Flush();
                    ras.Seek(0);
                    var decoder = BitmapDecoder.CreateAsync(ras).AsTask().GetAwaiter().GetResult();
                    return decoder.GetSoftwareBitmapAsync().AsTask().GetAwaiter().GetResult();
                }
            }
        }
    }
}
