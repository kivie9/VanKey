# VanKey Design System

All UI styling comes from **one place**: `app/lib/app/theme.dart`. Screens do not write colour codes or loose styles.
No external UI library is used: Flutter's Material components are used, but fully customised through the theme.

## Colours (taken from the prototype)

| Role | Light | Dark (true black) |
|---|---|---|
| `page` page background | `#F4F5F7` | `#000000` |
| `card` cards, dialogs, bottom bar | `#FFFFFF` | `#0F0F11` |
| `field` input fields | `#FFFFFF` | `#131315` |
| `line` thin dividers | `#E3E6EA` | `#232327` |
| `fg` / `muted` text | `#15171A` / `#6B7280` | `#F2F2F5` / `#9A9AA3` |
| `accent` accent colour | teal `#0B7A6B` (6 colours can be chosen) | `#4BC6B0` (lighter for enough contrast) |
| `warn` / `danger` / `success` | `#B45309` / `#B42318` / `#15803D` | `#F5A54A` / `#FF8A7A` / `#5FD38D` |

Get colours in code with: `AppColors.of(context)` or `Theme.of(context).colorScheme`.

## Spacing and corner radius

`Gap` (4, 8, 12, 16, 24, 32) and `Radii` (8, 12, 16, 20). Cards have radius 16; input fields and buttons radius 12; dialogs radius 20.

## Components

- **Input fields:** `field` background, thin `line` border with radius 12; when focused, a 1.6 px accent border and an accent floating label. Screens must **not** set their own `border`.
- **Buttons:** `FilledButton` (primary), `OutlinedButton` (secondary, card background), `TextButton` (accent-coloured text); height 50, radius 12.
- **Grouped cards:** `SectionCard` (several rows, thin dividers between rows), `GroupedRow` (for long, lazy lists).
- **Others:** `SectionHeader`, `IconBadge`, `Notice` (info, warning, error), `EmptyState`, `StrengthMeter`, `AppLogo`, `TotpChip`. Located in `lib/app/widgets/`.
- **Menus, dialogs, bottom sheets, snackbars, chips, switches, navigation bars:** each has its own theme in `theme.dart`.

## Desktop layout

Windows wider than 840 px use `screens/desktop_home.dart`, following the "Desktop (Windows)" mode of the prototype: a top bar, a 200 px menu column (All, each type, cards, 2FA codes, Tools, Settings), a card grid with a minimum width of 300 px, and item details opened in a dialog. Narrower windows use the phone layout. An intentional difference from the prototype: the Vault list does not show items and 2FA codes (they have their own tabs), and there is an extra "Tools" entry.

## Grouping by service

A "Service" grouping mode (next to Card, Type, No grouping): services with two or more accounts are placed into one card that opens on tap; while searching, it is already open. Within a group, items with the same service name show the username on the main line.

- The service is **computed**, not stored in the vault (`lib/core/vault/services.dart`): by the domain of the web address; without an address, by the whole item name.
- Only an exact domain or subdomain match counts: `facebook.com.trang-la.ru` is not Facebook. `brandFor` (which guesses logos) is not used for grouping.
- The "Service" field in the form is only a quick selector; it fills in the web address and the name.
- Old login items with no address but a name similar to a service: the app asks on the details screen and in Tools → Service suggestions. The app only changes anything when you tap "Yes"; a "No" answer is stored in the device's settings.

## Viewing the UI while editing

No need to open a phone. A test takes screenshots of the main screens (light and dark) into `app/build/screens/`:

```powershell
cd app
flutter test test/tool/screenshots_test.dart --dart-define=VK_SHOTS=true
```

This test loads the app's actual fonts, so the text renders correctly. Desktop-layout images are named `2x_may_tinh_*`. A normal `flutter test` run skips it automatically.

## Technical notes

- Shadows (`elevation`) are not used for cards, menus or dialogs: thin borders are used instead. Only the round add button has an accent-coloured glow.
- Fonts are bundled in `app/assets/fonts` (OFL licence, included in the folder), identical on Windows and Android. Font family names come from `Fonts` in `theme.dart`: `body` (Inter) for regular text, `head` (Space Grotesk, up to weight 700) for headings, `mono` (JetBrains Mono) for 2FA codes, passwords and keys.
