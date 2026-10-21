# Third-Party Notices

T-Utilities (MIT, see LICENSE) includes code adapted from the following projects.

## CopyNinja — `Packages/ModClipboard`

https://github.com/dwyi84/CopyNinja

```
MIT License

Copyright (c) 2026 Dawoon Yi / MelissaSoft

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Rectangle — `Packages/ModWindows`

https://github.com/rxhanson/Rectangle

```
MIT License

Copyright (c) 2019-2026 Ryan Hanson
Based on the Spectacle app, Copyright (c) 2017 Eric Czarny eczarny@gmail.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## WhatCable — `Vendor/WhatCable` (unmodified, git subtree), used by `Packages/ModCable`

https://github.com/darrylmorley/whatcable

```
MIT License

Copyright (c) 2026 Darryl Morley

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
```

WhatCable in turn includes code ported from edid-decode (v4l-utils), reproduced from
`Vendor/WhatCable/THIRD_PARTY_NOTICES.md`:

### edid-decode (v4l-utils)

`Sources/WhatCableCore/Display/EDIDTimingFormulas.swift` is a port of
`calc_gtf_mode` and `calc_cvt_mode` from `utils/edid-decode/calc-gtf-cvt.cpp`
in v4l-utils, commit `f341ed8e3742118a86619e5f499017db2de30d94`.

`Sources/WhatCableCore/Display/EDIDBaseBlockParser.swift` and
`Sources/WhatCableCore/Display/EDIDEstablishedTimings.swift` carry byte
layouts, offsets and threshold values ported from
`utils/edid-decode/parse-base-block.cpp` at the same commit: the base-block
descriptor decode (Established Timings I/II/III, Standard Timings, Detailed
Timing Descriptors, the 0xFD Display Range Limits and 0xF8 CVT 3-byte code
descriptors), and the `established_timings3_dmt_ids[]` table (the 44 DMT ids
Established Timings III's bitmap indexes).

`EDIDEstablishedTimings.legacy`'s four non-DMT rows (two IBM 720x400 modes,
Apple 640x480@67 and Apple 832x624@75) carry hTotal/vTotal/pixelClockKHz
figures for those named hardware standards, verified against edid-decode's
own printed output (`edid-decode-bin`, run on the real G34w-10 fixture in
`EDIDInfoTests.baseBlockG34wEstablishedTimings`).

These three files are the only ones in this repository that carry ported
code.

Copyright lines from the header of `calc-gtf-cvt.cpp`:

    Copyright 2006-2012 Red Hat, Inc.
    Copyright 2018-2021 Cisco Systems, Inc. and/or its affiliates. All rights reserved.

    Author: Adam Jackson <ajax@nwnk.net>
    Maintainer: Hans Verkuil <hverkuil+cisco@kernel.org>

Licence (`utils/edid-decode/LICENSE`, SPDX-License-Identifier: MIT), reproduced
verbatim:

    Copyright 2006-2012 Red Hat, Inc.
    Copyright 2018-2024 Cisco Systems, Inc. and/or its affiliates. All rights reserved.

    Permission is hereby granted, free of charge, to any person obtaining a
    copy of this software and associated documentation files (the "Software"),
    to deal in the Software without restriction, including without limitation
    on the rights to use, copy, modify, merge, publish, distribute, sub
    license, and/or sell copies of the Software, and to permit persons to whom
    the Software is furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice (including the next
    paragraph) shall be included in all copies or substantial portions of the
    Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NON-INFRINGEMENT.  IN NO EVENT SHALL
    THE AUTHORS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
    IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
    CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

## LinearMouse — `Packages/ModMouse`

https://github.com/linearmouse/linearmouse — pointer speed/acceleration (PointerKit), Dock actions (DockKit),
scroll transforms and Logitech HID++ battery reading were adapted (rewritten in reduced form) from LinearMouse.

    MIT License

    Copyright (c) 2021-2024 LinearMouse

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.

## Design references (no code copied)

- eclam (MIT, https://github.com/jadhvank/eclam) — agent-activity detection approach.
- Amphetamine Enhancer (MIT, https://github.com/x74353/Amphetamine-Enhancer) — rootless closed-display approach.
- allkdic / 올ㅋ사전 (MIT, https://github.com/devxoul/allkdic) — idea of a hotkey-toggled Naver/Daum dictionary panel; no code copied.
- easy-move-resize (MIT, © Daniel Marcotte, https://github.com/dmarcotte/easy-move-resize) — modifier + drag to move/resize a window from anywhere inside it. Idea only; the code is a fresh implementation.

## KeyboardShortcuts (dependency)

https://github.com/sindresorhus/KeyboardShortcuts — MIT License, © Sindre Sorhus
