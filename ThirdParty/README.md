# Third-party SDKs

## NDI SDK for Apple

`ThirdParty/NDI/` (headers + `libndi_ios.a`) is **not** committed to this
repo — it's a 256MB licensed binary from NewTek/Vizrt, and redistributing
it here would both blow past GitHub's file-size limit and isn't ours to
redistribute.

To build the NDI Output feature locally:

1. Download and install the "NDI SDK for Apple" from
   [ndi.video/for-developers](https://ndi.video/for-developers/).
2. Copy the SDK's `include/` and `lib/iOS/libndi_ios.a` into
   `ThirdParty/NDI/include/` and `ThirdParty/NDI/lib/` respectively
   (create those folders if needed):

   ```bash
   mkdir -p ThirdParty/NDI/include ThirdParty/NDI/lib
   cp "/Library/NDI SDK for Apple/include/"*.h ThirdParty/NDI/include/
   cp "/Library/NDI SDK for Apple/lib/iOS/libndi_ios.a" ThirdParty/NDI/lib/
   ```

The Xcode project's `HEADER_SEARCH_PATHS`/`LIBRARY_SEARCH_PATHS` already
point at these folders — nothing else to configure.

Note: this particular SDK build's `libndi_ios.a` only has `arm64` (real
device) and `x86_64` (Intel Simulator) slices — no `arm64` Simulator
slice. The project's build settings exclude `arm64` for Simulator builds
so Xcode falls back to the `x86_64` slice (runs under Rosetta on Apple
Silicon Macs) instead of failing to link. NDI itself is also best tested
on a real device anyway, since it needs real local-network/Bonjour
discovery.
