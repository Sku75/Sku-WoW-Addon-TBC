using System;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Imaging;
using System.Runtime.InteropServices;
using System.Threading;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;
using Windows.Graphics.Imaging;

namespace SkuLoginSense
{
    /// <summary>
    /// Captures the WoW window's client area as a Bitmap.
    /// Primary path: Windows.Graphics.Capture (same OS API OBS/Discord use;
    /// works for D3D content and doesn't require the window in the foreground).
    /// Fallback: GDI PrintWindow(PW_RENDERFULLCONTENT), then screen BitBlt.
    /// Sensing stays strictly out-of-process - hard rule of the rework.
    /// </summary>
    public static class WindowCapture
    {
        // ---------- window lookup ----------

        static readonly string[] DefaultExeNames = { "WowClassic", "Wow", "WowT" };

        public static IntPtr FindWowWindow(string exeName, string titleSubstring, out string foundDescription)
        {
            foundDescription = null;
            if (!string.IsNullOrEmpty(titleSubstring))
            {
                IntPtr byTitle = IntPtr.Zero;
                string desc = null;
                EnumWindows((hwnd, l) =>
                {
                    if (!IsWindowVisible(hwnd)) return true;
                    string t = GetWindowTitle(hwnd);
                    if (t.IndexOf(titleSubstring, StringComparison.OrdinalIgnoreCase) >= 0)
                    {
                        byTitle = hwnd;
                        desc = "title '" + t + "'";
                        return false;
                    }
                    return true;
                }, IntPtr.Zero);
                foundDescription = desc;
                return byTitle;
            }

            var names = string.IsNullOrEmpty(exeName) ? DefaultExeNames : new[] { exeName };
            foreach (var name in names)
            {
                foreach (var p in Process.GetProcessesByName(name))
                {
                    if (p.MainWindowHandle != IntPtr.Zero)
                    {
                        foundDescription = name + ".exe pid " + p.Id + " '" + GetWindowTitle(p.MainWindowHandle) + "'";
                        return p.MainWindowHandle;
                    }
                }
            }
            return IntPtr.Zero;
        }

        static string GetWindowTitle(IntPtr hwnd)
        {
            var sb = new System.Text.StringBuilder(512);
            GetWindowText(hwnd, sb, sb.Capacity);
            return sb.ToString();
        }

        // ---------- capture ----------

        public static Bitmap CaptureClientArea(IntPtr hwnd, out string method)
        {
            GetWindowRect(hwnd, out RECT wr);
            GetClientRect(hwnd, out RECT cr);
            var clientOrigin = new POINT();
            ClientToScreen(hwnd, ref clientOrigin);
            int clientW = cr.Right - cr.Left, clientH = cr.Bottom - cr.Top;
            int offX = clientOrigin.X - wr.Left, offY = clientOrigin.Y - wr.Top;

            try
            {
                using (var full = CaptureWithWgc(hwnd))
                {
                    method = "wgc";
                    return CropToClient(full, offX, offY, clientW, clientH);
                }
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine("WGC capture failed (" + ex.Message + "), falling back to GDI");
            }

            var gdi = CaptureWithPrintWindow(hwnd, wr);
            if (gdi != null && !LooksBlank(gdi))
            {
                method = "printwindow";
                return CropToClient(gdi, offX, offY, clientW, clientH);
            }
            gdi?.Dispose();

            method = "screencopy";
            var bmp = new Bitmap(clientW, clientH, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
                g.CopyFromScreen(clientOrigin.X, clientOrigin.Y, 0, 0, new Size(clientW, clientH));
            return bmp;
        }

        static Bitmap CropToClient(Bitmap full, int offX, int offY, int clientW, int clientH)
        {
            // WGC/PrintWindow deliver the whole window incl. chrome; cut out the
            // client area. Borderless fullscreen (the WoW default) is a no-op crop.
            if (offX == 0 && offY == 0 && full.Width == clientW && full.Height == clientH)
                return (Bitmap)full.Clone();
            var rect = new Rectangle(
                Math.Max(0, Math.Min(offX, full.Width - 1)),
                Math.Max(0, Math.Min(offY, full.Height - 1)),
                Math.Min(clientW, full.Width - offX),
                Math.Min(clientH, full.Height - offY));
            return full.Clone(rect, PixelFormat.Format32bppArgb);
        }

        static bool LooksBlank(Bitmap bmp)
        {
            // PrintWindow returns black frames for some D3D swapchains; sample a grid.
            int nonBlack = 0;
            for (int y = 1; y < bmp.Height; y += Math.Max(1, bmp.Height / 8))
                for (int x = 1; x < bmp.Width; x += Math.Max(1, bmp.Width / 8))
                {
                    var c = bmp.GetPixel(x, y);
                    if (c.R > 8 || c.G > 8 || c.B > 8) nonBlack++;
                }
            return nonBlack < 3;
        }

        static Bitmap CaptureWithPrintWindow(IntPtr hwnd, RECT wr)
        {
            int w = wr.Right - wr.Left, h = wr.Bottom - wr.Top;
            if (w <= 0 || h <= 0) return null;
            var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            using (var g = Graphics.FromImage(bmp))
            {
                IntPtr hdc = g.GetHdc();
                bool ok;
                try { ok = PrintWindow(hwnd, hdc, PW_RENDERFULLCONTENT); }
                finally { g.ReleaseHdc(hdc); }
                if (!ok) { bmp.Dispose(); return null; }
            }
            return bmp;
        }

        // ---------- Windows.Graphics.Capture via WinRT interop ----------

        static Bitmap CaptureWithWgc(IntPtr hwnd)
        {
            IntPtr d3dDevice = IntPtr.Zero, context = IntPtr.Zero, dxgiDevice = IntPtr.Zero, inspectable = IntPtr.Zero;
            try
            {
                int hr = D3D11CreateDevice(IntPtr.Zero, D3D_DRIVER_TYPE_HARDWARE, IntPtr.Zero,
                    D3D11_CREATE_DEVICE_BGRA_SUPPORT, IntPtr.Zero, 0, D3D11_SDK_VERSION,
                    out d3dDevice, out _, out context);
                if (hr != 0) Marshal.ThrowExceptionForHR(hr);

                var iidDxgi = IID_IDXGIDevice;
                hr = Marshal.QueryInterface(d3dDevice, ref iidDxgi, out dxgiDevice);
                if (hr != 0) Marshal.ThrowExceptionForHR(hr);

                hr = CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice, out inspectable);
                if (hr != 0) Marshal.ThrowExceptionForHR(hr);
                var device = (IDirect3DDevice)Marshal.GetObjectForIUnknown(inspectable);

                var factory = System.Runtime.InteropServices.WindowsRuntime.WindowsRuntimeMarshal
                    .GetActivationFactory(typeof(GraphicsCaptureItem));
                var interop = (IGraphicsCaptureItemInterop)factory;
                var iidItem = IID_GraphicsCaptureItem;
                IntPtr itemPtr = interop.CreateForWindow(hwnd, ref iidItem);
                var item = (GraphicsCaptureItem)Marshal.GetObjectForIUnknown(itemPtr);
                Marshal.Release(itemPtr);

                using (var pool = Direct3D11CaptureFramePool.CreateFreeThreaded(
                    device, DirectXPixelFormat.B8G8R8A8UIntNormalized, 2, item.Size))
                using (var session = pool.CreateCaptureSession(item))
                {
                    try { session.IsCursorCaptureEnabled = false; } catch { /* pre-1809 */ }
                    session.StartCapture();

                    Direct3D11CaptureFrame frame = null;
                    var sw = Stopwatch.StartNew();
                    while (frame == null && sw.ElapsedMilliseconds < 3000)
                    {
                        frame = pool.TryGetNextFrame();
                        if (frame == null) Thread.Sleep(15);
                    }
                    if (frame == null) throw new TimeoutException("no WGC frame within 3s");

                    using (frame)
                    {
                        var sb = SoftwareBitmap.CreateCopyFromSurfaceAsync(frame.Surface, BitmapAlphaMode.Ignore)
                            .AsTask().GetAwaiter().GetResult();
                        using (sb) return SoftwareBitmapToBitmap(sb);
                    }
                }
            }
            finally
            {
                if (inspectable != IntPtr.Zero) Marshal.Release(inspectable);
                if (dxgiDevice != IntPtr.Zero) Marshal.Release(dxgiDevice);
                if (context != IntPtr.Zero) Marshal.Release(context);
                if (d3dDevice != IntPtr.Zero) Marshal.Release(d3dDevice);
            }
        }

        static Bitmap SoftwareBitmapToBitmap(SoftwareBitmap sb)
        {
            int w = sb.PixelWidth, h = sb.PixelHeight;
            var buffer = new Windows.Storage.Streams.Buffer((uint)(w * h * 4));
            sb.CopyToBuffer(buffer);
            byte[] bytes = System.Runtime.InteropServices.WindowsRuntime.WindowsRuntimeBufferExtensions.ToArray(buffer);

            var bmp = new Bitmap(w, h, PixelFormat.Format32bppArgb);
            var bd = bmp.LockBits(new Rectangle(0, 0, w, h), ImageLockMode.WriteOnly, PixelFormat.Format32bppArgb);
            try
            {
                for (int y = 0; y < h; y++)
                    Marshal.Copy(bytes, y * w * 4, bd.Scan0 + y * bd.Stride, w * 4);
            }
            finally { bmp.UnlockBits(bd); }
            return bmp;
        }

        // ---------- native ----------

        const int D3D_DRIVER_TYPE_HARDWARE = 1;
        const uint D3D11_CREATE_DEVICE_BGRA_SUPPORT = 0x20;
        const uint D3D11_SDK_VERSION = 7;
        const uint PW_RENDERFULLCONTENT = 2;
        static readonly Guid IID_IDXGIDevice = new Guid("54ec77fa-1377-44e6-8c32-88fd5f44c84c");
        static readonly Guid IID_GraphicsCaptureItem = new Guid("79C3F95B-31F7-4EC2-A464-632EF5D30760");

        [ComImport, Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
        interface IGraphicsCaptureItemInterop
        {
            IntPtr CreateForWindow([In] IntPtr window, [In] ref Guid iid);
            IntPtr CreateForMonitor([In] IntPtr monitor, [In] ref Guid iid);
        }

        [DllImport("d3d11.dll")]
        static extern int D3D11CreateDevice(IntPtr pAdapter, int driverType, IntPtr software, uint flags,
            IntPtr pFeatureLevels, uint featureLevels, uint sdkVersion,
            out IntPtr ppDevice, out IntPtr pFeatureLevel, out IntPtr ppImmediateContext);

        [DllImport("d3d11.dll")]
        static extern int CreateDirect3D11DeviceFromDXGIDevice(IntPtr dxgiDevice, out IntPtr graphicsDevice);

        delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool EnumWindows(EnumWindowsProc cb, IntPtr lParam);
        [DllImport("user32.dll")] static extern bool IsWindowVisible(IntPtr hWnd);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder text, int count);
        [DllImport("user32.dll")] static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
        [DllImport("user32.dll")] static extern bool GetClientRect(IntPtr hWnd, out RECT rect);
        [DllImport("user32.dll")] static extern bool ClientToScreen(IntPtr hWnd, ref POINT point);
        [DllImport("user32.dll")] static extern bool PrintWindow(IntPtr hWnd, IntPtr hdc, uint flags);

        [StructLayout(LayoutKind.Sequential)] struct RECT { public int Left, Top, Right, Bottom; }
        [StructLayout(LayoutKind.Sequential)] struct POINT { public int X, Y; }
    }
}
