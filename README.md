# BigMig for MiSTer

A **Big Box Amiga** for the MiSTer board: the Minimig chipset in the FPGA fabric, driven by a
68k that is not in the fabric at all.

BigMig replaces the in-fabric soft CPU with **Emu68-A9**, an ARMv7 just-in-time recompiler
running bare-metal on the second ARM core of the DE10-Nano's HPS. The Amiga custom chips —
Agnus, Denise, Paula, Gary, the CIAs — are the same cycle-accurate Minimig logic they have
always been. Only the processor moved.

The result is an Amiga that is **520 MIPS** where Minimig's TG68K is about 12 — selectable as
a **68EC020 or a 68040**, with a **68882-class FPU** and an open SIMD extension — and whose
chip RAM is nonetheless **faster than a real A600's**.

> **BigMig is a separate core from Minimig, on purpose.** Minimig for MiSTer is excellent and
> mature, and thousands of people have configurations that work. This core diverges in what it
> offers — that is the point of it — and a divergent core has no business overwriting their
> setup. Nothing here touches Minimig: separate `.rbf`, separate config, separate saves. The
> only thing the two share is that BigMig points at the same `/games/Amiga` folder, so your
> disks and hard-drive images are found without copying anything.

---

## The first attempt was Mark Watson's

A hybrid core — the FPGA doing the chipset, an ARM core doing the CPU — had been talked about in
the MiSTer community for years, by Sorgelig among others, and by me. Talking about it is easy.

**Mark Watson built one.** Minimig Hybrid was the first actual attempt, and BigMig exists because
of it: it showed the thing could be made to run at all, and the earliest register blocks of our
seam were his code. That is worth honouring, and we do.

What we did differently is concentrated in one area: **how the two ARM cores are used**, because
that is where responsiveness is won or lost.

* **Core #1 runs bare metal, and only the firmware.** No Linux scheduler on it, no other
  process, no sharing — the JIT owns the core outright. Linux is booted with `maxcpus=1` so it
  never has a claim on it in the first place (that is what the sidecar file below is for).
* **Core #0 runs MiSTer's Main with an explicit priority order**: **USB polling first**, at the
  same **1 ms** rate as official Main, then the **OSD**, then the **hard-drive device**. Input
  is never queued behind anything. Disk work — the only part that can afford to wait — waits.
* **Emu68 was ported to the Cortex-A9.** Michal Schulz's Emu68 targets AArch64; the A9 on the
  DE10-Nano is 32-bit ARMv7. The JIT's code generator, its cache maintenance and its exception
  paths were rebuilt for that target, which is what makes a bare-metal 68k possible on this
  board at all.

Those three together are what make BigMig both fast *and* comfortable to actually use. "It is
very fast" would only be half a claim; the other half is that it feels like an FPGA core.

---

## What it is

| | |
|---|---|
| **CPU** | **68EC020 or 68040**, per config from the OSD, via the Emu68-A9 JIT — **520 MIPS**, on a dedicated ARM core |
| **FPU** | 68882-class, **double precision** — switchable on the 020, on-chip on the 040 |
| **SIMD** | **OMMX** — an open vector extension; the AMMX instruction set is a subset, so AMMX software runs |
| **Chipset** | OCS / ECS / AGA — unmodified Minimig logic, in the fabric |
| **Chip RAM** | up to 2 MB, on a dedicated path (see below) |
| **Fast RAM** | 264 MB, served by the JIT from HPS DDR3 |
| **RTG** | **ZZ9000** Zorro III graphics, up to 1920×1080, ARM-native blitter |
| **Ethernet** | the **ZZ9000 network function** — the stock `ZZ9000Net.device` takes a DHCP lease and holds a routed IP session on the real LAN |
| **16-bit audio** | **bigmigAHI** — a 16-bit card of our own, with the `bigmigAHI.audio` AHI driver we wrote: 8 streams, 16-bit stereo, mixed on the ARM |
| **Hard disk** | **bigmigHD.device** — autoboot, HDF images **and raw partition images** |
| **CD** | up to four drives — ISO, CUE and CHD, hot-swappable |
| **Floppy** | ADF, normal and turbo |
| **Kickstart** | 1.3, 2.0, 3.1, 3.2, 3.2.2 — including **1 MB ROMs** (512K ext-ROM + 512K Kickstart) |
| **Video / audio / input** | the MiSTer framework, as every other core |

### Not here, and deliberately

* **No slow RAM.** The memory map this core is built around does not have it.
* **No soft CPU.** `fx68k` and `TG68K` are gone from the fabric, not parked — the seam is the
  only chip-bus master. That is what frees the logic and the timing margin.
* **No MiSTer RTG card.** ZZ9000 replaces it.
* **No Gayle IDE.** Storage goes through `bigmigHD.device`.
* **No MMU translation.** The 68040 answers its full MMU register set and stores what you
  write, but translation is never enabled — software that *probes* the MMU is happy, software
  that needs real remapping is out of scope.

---

## Measured

SysInfo 4.4, same install, both personalities:

| presented CPU | MIPS | MFlops | vs A600 |
|---|---|---|---|
| 68EC020 + 68882 | **520.16** | 20.51 | ~940× |
| 68040 | 517.74 | 19.38 | ~930× |

* **Over 43×** Minimig's TG68K with Data Cache.
* As a 68040 the OS confirms it end to end: SysInfo reads *68040 / 68040+68882 / MMU 68040
  (not in use)*, and WhichAmiga reads *MC68040, 68040fpu*.

Chip-RAM accesses do not go over the Amiga chip bus. They go down the memory controller's own CPU port, where a cycle completes when SDRAM actually commits it rather than when arbitration says so. Agnus keeps absolute priority for DMA.

---

## Getting started

### Install

BigMig ships its own build of MiSTer's Main. **Install it as a second binary, not in place of
yours** — that way it runs only when you load BigMig, and the rest of your machine is untouched.

1. Copy `MiSTer_BigMig` from the release to `/media/fat/` — a **new file**, and it already
   carries the name it must have. Leave your official `/media/fat/MiSTer` alone.
2. Add this to `MiSTer.ini`:

```ini
[BigMig]
main=MiSTer_BigMig
```

| from the release | goes to |
|---|---|
| `BigMig_YYYYMMDD.rbf` | `/media/fat/_Computer/`, or the card root |
| `BigMig_YYYYMMDD.txt` | **beside the `.rbf`** |
| `Emu68.img` | `/media/fat/linux/Emu68.img` |
| `MiSTer_BigMig` | `/media/fat/` — **do not rename it to `MiSTer`** |

Then put a Kickstart ROM where you already keep Minimig's.

Those four files are the machine.  The release also carries **guest-side** files — they go
inside the Amiga's own filesystem, not on the SD card root, and none of them is required to
boot:

| from the release | goes to, inside the Amiga | for |
|---|---|---|
| `bigmigAHI.audio` | `DEVS:AHI/` | 16-bit sound — **pair with the next line** |
| `bigmigAHI` | `DEVS:AudioModes/` | the AHI mode descriptor; without it the driver is invisible |
| `ZZ9000.card` | `LIBS:Picasso96/` | RTG graphics — the board driver |
| `Monitors/ZZ9000` + `.info` | `DEVS:Monitors/` | the RTG monitor |
| `Picasso96Settings` | `DEVS:` | the RTG mode list |
| `DOSDrivers/CD0`…`CD3` | `DEVS:DOSDrivers/` | CD drives — one file per drive, install only the ones you want |
| `ZZ9000Net.device` | `DEVS:Networks/` | ethernet (you supply the TCP/IP stack) |
| `NetInterfaces/ZZ9000Net` | `DEVS:NetInterfaces/` | a sample interface config, edit to taste |

⚠ The two `bigmigAHI` files are a **pair**: the driver alone offers no modes, the mode file
alone drives nothing.  Ship and install them together.

⚠ **Picasso96 itself is not ours to ship.**  The release carries every ZZ9000 RTG file, but the
RTG *system* those files plug into is Picasso96, which you install first.  The last freely
distributable version is **Picasso96 2.0** on Aminet:
[`driver/video/Picasso96.lha`](https://aminet.net/package/driver/video/Picasso96).

⚠ **Why a second binary.** BigMig is under active development. Keeping its Main separate means
nothing of ours runs unless you load BigMig: your official Main stays exactly where it is, the
updater keeps maintaining it, and the rest of your machine is untouched by whatever we change
next.

⚠ **The `.rbf` and the `.txt` must sit in the same folder and keep the same name.** The `.txt` is
one line of Linux boot arguments that hands ARM core #1 to the firmware, and the loader finds it
by taking the core's own filename. Split them, or rename one without the other, and the core
starts with no CPU.

⚠ **`Emu68.img` keeps that exact name**, in `/media/fat/linux/`. It is the firmware, not a disk
image.

⚠ **Do not mix releases.** Firmware and gateware are versioned and tested together; taking one
file from an older set is the first thing to undo if something behaves strangely.

### The sidecar, briefly

`BigMig.txt` sits next to `BigMig.rbf` and contains one line of Linux boot arguments —
`maxcpus=1`. It is the **official MiSTer per-core boot-args mechanism**, not something we
invented.

It exists because a core that hands an ARM core to a bare-metal JIT cannot have Linux
scheduling on that core. Loading BigMig reloads Linux with those arguments, so core #1 arrives
at the hybrid launch never having entered the new Linux instance at all. Loading any other core
reloads Linux without them, and that core gets its two CPUs back.

⚠ Both files must be present. `BigMig.rbf` without `BigMig.txt` will not start correctly.

### Where the settings live

Two OSD pages, and the split is deliberate: one is about the **processor**, the other about the
**machine**.

**Emu68-A9** — Mode, JIT Cache, 68882, OMMX, JITSTATS.  Everything that describes the CPU you
are running.

**System** — Chipset and RAM, then **Zorro Boards**: ZZ9000 RTG, ZZ9000 Network, BigMig AHI.
Then the usual Joystick, ROM and HRTmon.

Every setting is saved with the config slot, so a slot can be a whole machine: a 68040 with the
RTG and no sound for one title, an 020 with everything for another.

⚠ **On a board, OFF means ABSENT, not idle.**  The card leaves the autoconfig chain entirely and
the firmware stops spending anything on it, so the guest never sees it and the emulation core
never pays for it.  That is the point: a configuration should not be taxed for hardware it does
not use.  The exception is ZZ9000 Network, whose bridge runs on the Linux core and which
therefore applies the instant you press it; everything else takes effect at the next Reset.

### JIT Cache

One row on the Emu68-A9 page, saved per config slot, changeable live. It is a **compatibility** setting, not a
performance one: every step is slower than the one before, and they fix different things.

| setting | what it does |
|---|---|
| **64MB** | Normal speed. This is the default and it is what almost everything wants. |
| **0KB (compat)** | No translation cache at all. Slowest by far; the last resort when nothing else runs a title. |
| **64MB (verify)** | Emu68 checks each block itself instead of trusting a program to announce that it rewrote its own code. Many demos and WHDLoad titles never announce it, and the stale translation shows up as graphical glitches. |
| **64MB (chip speed)** | Re-translates only Chip RAM code, so that code is paced by the chip bus again, as on a real accelerator. This is what demos that time the CPU against the raster expect. The rest of the system stays fast. |
| **64MB (verify+chip)** | Both at once. One fixes correctness, the other fixes pacing — a demo that rewrites its own code *and* times itself against the raster needs both. Try it on anything the other two do not fix. |

If something behaves oddly, **try the default again before reporting it**, and tell us which
setting you used.

### Mode, FPU, OMMX and JITSTATS

The rest of the Emu68-A9 page, all saved per config and applied at the next Reset:

* **Mode: 68EC020 / 68040.** The personality is honest both ways: as an 020 the 68040-only
  instructions trap exactly as they should (WHDLoad's CPU probe depends on it), as an 040 the
  MOVEC register set, the cache instructions, PFLUSH/PTEST and the 040 stack frames are all
  answered — that is what SysInfo and WhichAmiga identify.
* **68882: ON / OFF.** A 68882-class FPU computing in double precision. On the 68040 it reads
  "ON (68040)" — that CPU carries its FPU on-chip.
* **OMMX: ON / OFF.** An open SIMD extension for this machine; the Apollo **AMMX** instruction
  set is a strict subset, so existing AMMX software (RiVA's video kernels, for instance) runs
  unmodified.  The spec is open — `docs/OMMX-SPEC.md` in the firmware repository — and worked
  examples exist.  A caveat worth knowing before porting code: OMMX buys *arithmetic*
  throughput; a display path that is memory-bound gains nothing, and we publish the
  measurements that show it.
* **JITSTATS: ON / OFF.**  Emu68's telemetry counters — the ones `jitstat` and Emu68Info read.
  They are cheap but **not free**: the m68k instruction counter is emitted into every
  translated block, and switching it off measures **2-3 MIPS** back.  Leave it OFF unless you
  are actually reading the counters.

### Ethernet

The ZZ9000's **network function** is implemented alongside its graphics: the stock
`ZZ9000Net.device` driver finds a wired card and reaches the real LAN.  The bridge runs on the
Linux core at the **lowest priority in Main's loop** — input, OSD and disk always come first —
and the OSD **ZZ9000 Network** row prices it honestly: OFF costs literally nothing (the socket
is never opened), ON costs about half a percent.  It is the one row that applies live — its
bridge is a Linux-side process, so switching it is the cable coming and going as far as the
guest is concerned.

The guest negotiates DHCP, resolves its gateway by ARP, and answers pings from other machines
on the LAN.  The card presents its own MAC address, so a stock driver and a stock TCP/IP stack
are all it needs — you supply the stack (Roadshow, AmiTCP), the core supplies the card.

### 16-bit audio: the bigmigAHI card

Paula is four DMA voices of 8-bit PCM, and AHI's own `paula.audio` reaches about **14 bits** on
two of them by pairing channels at different volumes.  That is more than the chip is usually
given credit for, and it is still the machine's ceiling for modern work: the pairing costs half
the voices, the mixing is done by the 68k, and MP3 playback or a tracker wanting true 16-bit
output has nowhere to go.  So the core carries a 16-bit sound card of its own, **bigmigAHI**,
and the AHI sub-driver that binds it.

It is not an emulation of anyone else's board.  The card model and the mixing both run on the
firmware core, which leaves the Linux core free to serve the guest's disk and file requests —
music keeps playing while you open a drawer.  The card takes 8 independent streams of 16-bit
stereo, and the mixing arithmetic happens on the ARM, not on the emulated 68k: a Workbench
application hands the card a buffer and goes back to its own work.  Its output mixes with Paula's into whatever the MiSTer
framework outputs, so a game using Paula and a player using AHI coexist.

Two files make it work, and **they are a pair — either one alone does nothing**:

| file | goes to | what it is |
|---|---|---|
| `bigmigAHI.audio` | `DEVS:AHI/` | the AHI sub-driver |
| `bigmigAHI` | `DEVS:AudioModes/` | the mode descriptor AHI reads to offer the card |

Without the mode file AHI offers nothing and the driver is invisible to applications.  Both
ship in the release.  ⚠ AmigaOS matches library names **case-sensitively** once resident, so
the capitalisation above is functional, not cosmetic.

**On the Toccata.**  Minimig's **Toccata** — the MacroSystem 16-bit Zorro II card — is **not part
of BigMig**.  The module has been removed from the RTL, not merely switched off: it is not in
the gateware and there is nothing to enable.  bigmigAHI replaces it and fits this machine far
better — a Zorro II card is a 1990s I/O path bolted onto a bus, while bigmigAHI is a card model
running natively on the ARM, which is what the hybrid design is for.  The Toccata implementation
BigMig inherited was good work, and it stays in the project's history.

### CD drives

Up to four, and they behave like real drives rather than like files.

Put a `.iso`, `.cue` or `.chd` in one of the four drive slots on the OSD's **Drives** page. The
extension is enough — the row switches itself to **Removable/CD**, and there is no mode to set
first. The four slots map to the four drives in the order they are listed:

| slot on the Drives page | drive |
|---|---|
| Pri. Master | `CD0:` |
| Pri. Slave | `CD1:` |
| Sec. Master | `CD2:` |
| Sec. Slave | `CD3:` |

Install the matching mountfiles from the release into `DEVS:DOSDrivers/` — `CD0` through `CD3`,
one per drive, and only the ones you want. They need `L:CDFileSystem`, which comes with
Workbench; it is not ours to ship.

★ **A drive is permanent; the image is the disc.** Each `CDn` describes a drive that exists
whether or not anything is in it, so the mountfile is written once and never edited again.
Re-opening the slot with a different image *is* changing the disc: the drive's change counter
moves, the guest's drive task notices within a second and tells the file system. **No reset.**
Hard disks are not like this and still need one — pulling an FFS volume out from under a running
guest would take its cached state with it.

⛔ **`bigmigHD.device`, with a capital H and D.** exec's `FindName` compares exactly, so
`bigmighd.device` opens nothing — and it fails *silently*, looking exactly like a broken file
system. The shipped mountfiles have it right; this only bites if you write your own.

---

### Emu68 guest tools

The firmware implements Emu68's telemetry and control registers (MOVEC `$0E0-$0EB`): cycle
counter and its 800 MHz frequency, the executed-m68k-instruction counter, the JIT pool's
size/free/unit-count, and the two control registers — in **both** CPU personalities.  They
BigMig adopts the **same API** rather than inventing one, so a tool written for Emu68 needs no
port.

**Today**: the **jitstat** CLI reads the whole set — MIPS measured by the guest itself, live,
per title.  The counters are cheap but not free, so the **JITSTATS** row on the Emu68-A9 page
switches them off; leave it off unless you are reading them.

**Shortly**: **Emu68Info**.  It discovers hardware through `devicetree.resource`, which BigMig
does not publish yet — its own peripherals are found by autoconfig — and the tool runs the
moment that lands.  It is the next thing on this list.

---

## Reporting something that does not work

This core is new and it will have gaps. Reports are genuinely useful — but only if we can
reproduce them. Please include:

1. **Kickstart** version used
2. **Workbench** version used
3. **JIT configuration** (or "defaults")
4. **WHDLoad** — *with its version* — or the **ADF** used
5. **What happened**, and a **snapshot** if there is anything to see

The WHDLoad version matters more than people expect: one class of failure we chased for days
turned out to be a 1999 install against a 2023 one.

---

## Credits and licences

BigMig stands on other people's work, and most of the Amiga in it is theirs.

| part | authors | licence |
|---|---|---|
| **Minimig** — the original FPGA Amiga | Dennis van Weeren, Jakub Bednarski, Tobias Gubener, Sorgelig (Alexey Melnikov), Rok Krajnc and contributors | GPLv3 |
| **MiSTer framework** (`sys/`) | Sorgelig (Alexey Melnikov) and the MiSTer-devel project | GPLv3 |
| **Minimig Hybrid** — the first hybrid Minimig, and the original seam register blocks | Mark Watson | see the Minimig Hybrid project |
| **Emu68** — the JIT this port descends from | Michal Schulz | see the Emu68 project |
| **Emu68-A9** — the ARMv7 / Cortex-A9 port of Emu68 | Ruben Aparicio (@raparici) | as Emu68 |
| **bigmigHD.device** and its autoboot ROM | Ruben Aparicio (@raparici) — the careless-autoboot approach is inspired by Michal Schulz's `brdc` | GPLv3 |
| **ZZ9000 driver** | MNT Research / Lukas F. Hartmann and contributors; the Monitor included here is ours | see the ZZ9000 project |
| **The seam** — `axi_seam_slave`, `seam_engine`, `seam_ipl`, `seam_cpuregs`, `h2f_axi3_to_lite`, the hybrid bridge | Ruben Aparicio (@raparici) | GPLv3 |
| **MiSTer Main** (BigMig build) | MiSTer-devel, with our hybrid loader | GPLv3 |

⚠ **The firmware in this repository is a compiled binary.** Its source lives in its own
repository and is published separately, under its own licence.

If we have got an attribution wrong or left one out, please tell us — that is a bug like any
other.

---

The Amiga side of this core is Minimig's, and we track it. Changes that belong upstream should
go upstream.
