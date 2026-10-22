// Linux Mint ARM, virtual machines: Firefox renders in software. When Firefox draws with UTM's
// accelerated OpenGL (ANGLE, OpenGL 2.1), its text disappears.
pref("gfx.webrender.software", true);
pref("gfx.webrender.software.opengl", false);
