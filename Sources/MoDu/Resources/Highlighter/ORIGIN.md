# Highlight.js bundled asset provenance

- Product: Highlight.js
- Version: 11.12.0
- Upstream repository: https://github.com/highlightjs/cdn-release
- Upstream tag: `11.12.0`
- Upstream commit: `dce7a3dab8f3fd586138ba6c5f29ecc19c02db9f`
- Retrieved: 2026-08-27
- License: BSD 3-Clause (`LICENSE.txt`)

Bundled files and SHA-256 digests:

- `highlight.min.js`: `8ab71eb09c51f501e5e25157d9cff100e46cc29bcbfc744d0b746d451fca7f53`
- `dockerfile.min.js`: `d96f73b077d654d776795097cf49afae5dce3ce453106af022eae013ad2ec8b1`
- `groovy.min.js`: `55b81d783372ed6c8c99d5c3568113845dceb93ea454c54f61582ef8d2970a17`
- `gradle.min.js`: `03977cf861c7daafe75bbf9aa5bcb39f428fb5ea113ba282dde61f85fde6fe9e`
- `properties.min.js`: `8a987022cc566fa5bfcd79058ec4ba010920d576fff809b92317295827402590`
- `toml.min.js`: `cdfaf6fe726af73ea8c07b8eadaf681c8fb3b95ef4b9a7751f08c68e44ae7ea9`
- `LICENSE.txt`: `5f289f36595e0ef6c53d9f4b4e51d7cc1efc5e2b3ba6130a875d177c54789eaf`

The common browser build supplies the built-in language grammars. The four
additional language files are loaded only from the app's fixed, allowlisted
`modu-asset` URLs. No runtime CDN request is used.

`toml.min.js` is a small MoDu-owned Highlight.js language registration for
TOML keys, tables, literals, numbers, strings, and comments. It is maintained
as application source rather than copied from the upstream distribution.
