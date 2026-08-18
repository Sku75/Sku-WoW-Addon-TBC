using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Imaging;

namespace SkuLoginSense
{
    /// <summary>
    /// Pixel probing + screen classification over one captured frame.
    /// The UI coordinate math is a straight port of gameuihandling.ahk
    /// (UiToScreen / GetUiX), evaluated against the frame's own dimensions
    /// instead of the physical screen, so it works identically for live
    /// captures and for bundled screenshots.
    /// </summary>
    public sealed class Sensor : IDisposable
    {
        readonly GameData _data;
        readonly int _w, _h;
        readonly int[] _pixels; // ARGB rows, top-down

        public int Width => _w;
        public int Height => _h;

        public Sensor(Bitmap bmp, GameData data)
        {
            _data = data;
            _w = bmp.Width;
            _h = bmp.Height;
            _pixels = new int[_w * _h];
            var rect = new Rectangle(0, 0, _w, _h);
            using (var clone = bmp.PixelFormat == PixelFormat.Format32bppArgb ? null : bmp.Clone(rect, PixelFormat.Format32bppArgb))
            {
                var src = clone ?? bmp;
                var bd = src.LockBits(rect, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
                try
                {
                    for (int y = 0; y < _h; y++)
                        System.Runtime.InteropServices.Marshal.Copy(bd.Scan0 + y * bd.Stride, _pixels, y * _w, _w);
                }
                finally { src.UnlockBits(bd); }
            }
        }

        public void Dispose() { }

        // ---------- coordinate math (port of gameuihandling.ahk) ----------

        double EffectiveWidth(out double halfBar)
        {
            double w = _w;
            halfBar = 0;
            if ((double)_w / _h > 1.77)
            {
                w = _h * 1.7777777777777777;
                halfBar = (_w - w) / 2;
            }
            return w;
        }

        double GetUiX()
        {
            double ar = (double)_w / _h;
            if (ar < 1.34) return 960;
            if (ar < 1.49) return 1024;
            if (ar < 1.59) return 1152;
            if (ar < 1.77) return 1228.8;
            return 1365.33;
        }

        public void UiToPx(double x, double y, out int px, out int py)
        {
            double effW = EffectiveWidth(out double halfBar);
            double uiX = GetUiX();
            double sx;
            if (x >= 7000)      sx = ((x - 10000) / (uiX / 100)) * (effW / 100) + effW / 2; // anchor center
            else if (x <= 0)    sx = effW - (effW / 100) * ((-x) / (uiX / 100));            // anchor right
            else                sx = (x / (uiX / 100)) * (effW / 100);                       // anchor left
            // (the AHK AR<1 pillarbox special case is intentionally not ported -
            //  it only applies to portrait screens, which the game does not support)
            px = (int)Math.Round(sx + halfBar);
            py = (int)Math.Round(_h * (y / 768.0));
        }

        public GameData.Rgb ColorAtPx(int px, int py)
        {
            if (px < 0 || py < 0 || px >= _w || py >= _h) return new GameData.Rgb { R = -1, G = -1, B = -1 };
            int argb = _pixels[py * _w + px];
            return new GameData.Rgb { R = (argb >> 16) & 0xFF, G = (argb >> 8) & 0xFF, B = argb & 0xFF };
        }

        public GameData.Rgb ColorAtUi(double x, double y)
        {
            UiToPx(x, y, out int px, out int py);
            return ColorAtPx(px, py);
        }

        // ---------- fiducial checks (port of checks.ahk, BC-aware) ----------

        // +-5: fiducial colors live in DXT RGB565 endpoints whose GPU decode can
        // differ from the nominal value by a few units; all fiducials are far
        // enough apart that this cannot make two checks collide.
        static bool InRange(int test, int expect) => test >= expect - 5 && test <= expect + 5;

        bool Match(GameData.Rgb c, string colorName)
        {
            if (!_data.Colors.TryGetValue(colorName, out var e)) return false;
            return InRange(c.R, e.R) && InRange(c.G, e.G) && InRange(c.B, e.B);
        }

        bool Match(GameData.Rgb c, int r, int g, int b) => InRange(c.R, r) && InRange(c.G, g) && InRange(c.B, b);

        GameData.Rgb Widget(string name)
        {
            if (!_data.Widgets.TryGetValue(name, out var w)) return new GameData.Rgb { R = -1, G = -1, B = -1 };
            return ColorAtUi(w.X, w.Y);
        }

        bool IsBc => string.Equals(_data.Gametype, "BurningCrusade", StringComparison.OrdinalIgnoreCase);

        public bool IsLoginScreen()
        {
            if (IsBc)
            {
                // BC Anniversary has no yellow logo on the login screen (verified on
                // the bundled 2.5.5 screenshots). Quit + Create red, Addons not red
                // (Addons red = char selection, whose Back button is also red).
                return Match(Widget("LoginScreenQuit"), "GenericRedButton")
                    && Match(Widget("LoginScreenCreate"), "GenericRedButton")
                    && !Match(Widget("CharSelectionScreenAddons"), "GenericRedButton");
            }
            return Match(Widget("LoginScreenLogo"), "GenericLogo")
                && Match(Widget("LoginScreenQuit"), "GenericRedButton");
        }

        public bool IsLoginScreenInitialStart()
        {
            if (IsBc)
            {
                return Match(Widget("LoginScreenQuit"), "GenericRedButton")
                    && !Match(Widget("LoginScreenCreate"), "GenericRedButton")
                    && !Match(Widget("CharSelectionScreenAddons"), "GenericRedButton");
            }
            return Match(Widget("LoginScreenLogo"), "GenericLogo")
                && Match(Widget("LoginScreenQuit"), "GenericRedButton")
                && !Match(Widget("LoginScreenCreate"), "GenericRedButton");
        }

        public bool IsCharSelectionScreen()
        {
            bool addons = Match(Widget("CharSelectionScreenAddons"), "GenericRedButton");
            if (IsBc) return addons; // BC Anniversary has no yellow logo on CharSelect
            return addons && Match(Widget("CharSelectionScreenLogo"), "CharSelectionScreenLogo");
        }

        public bool IsCharCreationScreen()
        {
            bool backdrop = Match(Widget("CharCreationBackdrop"), "CharCreationBackdrop");
            if (IsBc) return backdrop && IsBcCharCreationLogoYellow();
            return backdrop && Match(Widget("CharCreationLogo"), "CharCreationLogo");
        }

        bool IsBcCharCreationLogoYellow()
        {
            // The BC logo drifts ~10 UI-px with the idle animation; accept any yellow hit.
            int[][] candidates = {
                new[]{108,68}, new[]{140,74}, new[]{110,78}, new[]{112,72}, new[]{136,72},
                new[]{140,78}, new[]{112,80}, new[]{110,70}, new[]{136,68}
            };
            foreach (var c in candidates)
            {
                var rgb = ColorAtUi(c[0], c[1]);
                if (rgb.R > 180 && rgb.G > 200 && rgb.B < 30) return true;
            }
            return false;
        }

        public bool IsRealmSelectionScreen()
        {
            return Match(Widget("RealmSelectionTitleBackdrop"), "RealmSelectionTitleBackdrop")
                && Match(Widget("RealmSelectionListBackdrop"), "RealmSelectionListBackdrop");
        }

        public bool IsContract()
        {
            return Match(Widget("CharSelectionScreenLogo"), "CharSelectionContractLogo")
                && Match(Widget("CharSelectionScreenAddons"), "CharSelectionContractAddons")
                && Match(ColorAtUi(9852, 284), "GenericBlack");
        }

        public bool IsOutdatedAddonsWarning()
        {
            bool normal = Match(Widget("CharSelectionScreenLogo"), "GenericLogo")
                       && Match(Widget("CharSelectionScreenAddons"), "GenericRedButton");
            bool dimmed = Match(Widget("CharSelectionScreenLogo"), 50, 57, 0)
                       && Match(Widget("CharSelectionScreenAddons"), "CharSelectionContractAddons");
            return (normal || dimmed) && Match(Widget("OutdatedAddonsWarningBackdrop"), 0, 40, 0);
        }

        public bool IsDeleteCharPopup()
        {
            return Match(Widget("DeleteCharPopupBackdrop"), 0, 40, 0)
                && Match(Widget("DeleteCharPopupEditBox"), 3, 17, 3);
        }

        public bool Is11Popup()
        {
            double probeY = IsBc ? 400 : 386; // BC OK button sits lower
            return Match(ColorAtUi(9915, probeY), "GenericRedButton") && !Is12Popup();
        }

        public bool Is21Popup()
        {
            return Match(ColorAtUi(9915, 412), "GenericRedButton") && !Is22Popup();
        }

        public bool Is12Popup()
        {
            return Match(ColorAtUi(9802, 386), "GenericRedButton")
                && Match(ColorAtUi(10196, 386), "GenericRedButton");
        }

        public bool Is22Popup()
        {
            return Match(ColorAtUi(9802, 412), "GenericRedButton")
                && Match(ColorAtUi(10196, 412), "GenericRedButton");
        }

        // The glue-dialog tint darkens the recolored red-button texture to
        // ~0.6 brightness (140 -> ~84; measured 79..91 over both buttons at
        // 2880x1800), so GenericRedButton's +-5 window can never match it.
        static bool IsGlueTintedRed(GameData.Rgb c) => c.R >= 75 && c.R <= 100 && c.G <= 8 && c.B <= 8;

        public bool IsHardcoreConfirm()
        {
            // The hardcore "death is permanent" confirmation shown when
            // joining a hardcore realm: two small red buttons ("Ich stimme
            // zu" / "Ablehnen") on one row BELOW every standard popup button
            // row, with the dialog's black body above and between them. The
            // gap probe kills the one-wide-button case (e.g. the reconnect
            // popup sits at almost the same height).
            // The gap between the buttons lands on the dialog's grey frame
            // strip (measured 46,41,38), so it is checked as "anything but a
            // red button", which is all it has to prove.
            var gap = Widget("HcConfirmGap");
            return IsGlueTintedRed(Widget("HcConfirmAcceptButton"))
                && IsGlueTintedRed(Widget("HcConfirmDeclineButton"))
                && !IsGlueTintedRed(gap) && !Match(gap, "GenericRedButton")
                && Match(Widget("HcConfirmBackdrop"), "GenericBlack");
        }

        public bool IsIngame()
        {
            // GenericBlue corner pixels are set by the Sku addon in-game.
            return Match(ColorAtPx(1, 1), "GenericBlue") || Match(ColorAtPx(1, _h - 2), "GenericBlue");
        }

        public Dictionary<string, bool> RunChecks()
        {
            return new Dictionary<string, bool>
            {
                ["login"] = IsLoginScreen(),
                ["loginInitial"] = IsLoginScreenInitialStart(),
                ["charselect"] = IsCharSelectionScreen(),
                ["charcreate"] = IsCharCreationScreen(),
                ["realmselect"] = IsRealmSelectionScreen(),
                ["contract"] = IsContract(),
                ["outdatedAddons"] = IsOutdatedAddonsWarning(),
                ["deletePopup"] = IsDeleteCharPopup(),
                ["popup11"] = Is11Popup(),
                ["popup21"] = Is21Popup(),
                ["popup12"] = Is12Popup(),
                ["popup22"] = Is22Popup(),
                ["hardcoreConfirm"] = IsHardcoreConfirm(),
                ["ingame"] = IsIngame(),
            };
        }

        /// <summary>Base screen identity; popups are reported separately in checks.</summary>
        public string Classify(Dictionary<string, bool> checks)
        {
            if (checks["ingame"]) return "ingame";
            if (checks["contract"]) return "contract";
            if (checks["hardcoreConfirm"]) return "hardcoreConfirm";
            if (checks["realmselect"]) return "realmselect";
            if (checks["charcreate"]) return "charcreate";
            if (checks["login"]) return "login";
            if (checks["charselect"]) return "charselect";
            return "unknown";
        }

        /// <summary>Every configured widget probe with its pixel position and color.</summary>
        public List<(string Name, double UiX, double UiY, int Px, int Py, GameData.Rgb Color)> ProbeAllWidgets()
        {
            var result = new List<(string, double, double, int, int, GameData.Rgb)>();
            foreach (var kv in _data.Widgets)
            {
                UiToPx(kv.Value.X, kv.Value.Y, out int px, out int py);
                result.Add((kv.Key, kv.Value.X, kv.Value.Y, px, py, ColorAtPx(px, py)));
            }
            return result;
        }
    }
}
