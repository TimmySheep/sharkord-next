# Apple mobile and Watch icon appearance variants

- Replaced the iPhone and iPad universal app icon with the supplied light image and added the
  supplied dark image as the `luminosity: dark` appearance. Enabled inclusion of all app icon
  assets so Xcode packages both variants while retaining the iOS 17 deployment target.
- Replaced the Watch app icon with the supplied light image. watchOS app icons use the light
  appearance; the platform does not provide the iPhone and iPad dark app-icon variants.
- Advanced the iPhone app, Live Activity extension, and Watch app to version `1.7`, build `8`.
- Verified Xcode asset output contains light and dark variants for both phone and iPad, and the
  Watch asset catalog compiles with the supplied 1024x1024 light icon. The Watch simulator build
  succeeded.
- The full iOS simulator build remains blocked by the existing non-exhaustive switch in
  `Sharkord/RootView.swift:11` for `.awaitingServerPassword`. Asset compilation succeeded before
  that unrelated Swift error. No simulator or physical device was operated.
- The change remains local and has not been pushed to GitHub.
