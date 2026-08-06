# MediaRemote Adapter

NookFlow bundles `mediaremote-adapter` at commit
`3ac3d4bdf862c7b5399b4fba4df5689f5c38609a`.

- Source: https://github.com/ungive/mediaremote-adapter
- License: BSD 3-Clause (`LICENSE`)
- Architectures: arm64 and x86_64
- Integration: the framework is bundled but not linked; `/usr/bin/perl` loads it for the long-running stream.

The stream uses the default incremental diff protocol with a 100 ms debounce.
The bundled binary also contains a NookFlow extension that emits a lightweight
`queue` event with next-track metadata. Queue artwork is deliberately omitted
to avoid adding large Base64 payloads to the long-running stream.
