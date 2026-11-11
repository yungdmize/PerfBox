# PerfBox

Performance meter for BeamNG.drive: 0-100, 100-200 km/h, 1/4 and 1/2 mile, 100-0 braking and more, with an automatic factory-style test. Works with any vehicle. English and Russian.

Everything is measured in the physics step (`onPhysicsStep`, 2000 Hz) on the simulation clock, so the results do not depend on FPS, the UI refresh rate or slow motion.

## What it measures

| Group | Runs | Also shown |
|---|---|---|
| Standing start | 0-60, 0-60 mph, 0-100, 0-150, 0-200, 0-250, 0-300 km/h | distance to that speed |
| Distance | 60 ft, 1/8 mile (201 m), 1/4 mile (402 m), 1/2 mile (805 m), 1 km, 1 mile | trap speed |
| Rolling | 60-100, 80-120, 100-200, 200-300 km/h | distance |
| Braking | 100-0 km/h | stopping distance |

Each run shows the last result and the best of the session. Fresh results of the current run are highlighted in orange.

## How it is measured

- **Speed:** the vehicle's horizontal ground speed, like a GPS logger.
- **Distance:** that speed integrated every physics step (0.5 ms).
- **Thresholds:** the moment a speed or distance is passed is interpolated inside the step.
- **Standing start:** stand still (< 0.3 km/h) for 0.3 s; the run triggers at 0.5 km/h and its clock is wound back to the moment the car started moving, as in published 0-100 figures.
- **Rollout 1 ft** (button): as on US drag strips, the clock starts after the first 0.3048 m; distances still count from rest.
- **Rolling intervals** count when the speed climbs through them without dropping below the lower bound.
- **Braking 100-0** starts when the speed falls through 100 km/h with the brake applied and ends at a full stop.

## Install

**BeamNG.Earth Add-ons page:** Settings → Add-ons → **Add from GitHub** → paste `yungdmize/PerfBox` → Install.

**By hand:** download `perfbox.zip` from the [latest release](../../releases/latest) and drop it, still zipped, into the `mods` folder of your BeamNG user folder (`%LOCALAPPDATA%\BeamNG\BeamNG.drive\current\mods`).

Then add the window in game: UI Apps → Add app → **PerfBox**.

## How to use

1. Stand still: the status shows "READY". Drive off: it shows "MEASURING".
2. **Reset** clears the results, **Rollout 1 ft** turns the US drag strip mode on.
3. The **−** button folds the window into one line (speed, status, 0-100, 100-200 and 402 m); **+** unfolds it. The state is remembered.
4. **Auto test:** the car holds on the parking brake for 2.5 s, then releases it and goes full throttle at the same moment (no brake torquing, no launch control), drives straight to 200 km/h and 402 m, then brakes. Player input is blocked meanwhile; the gearbox runs in arcade mode and the previous mode comes back afterwards. Only forward runs count.
5. **All configs:** the same for every configuration of the vehicle in turn, each from the same start point. A run ends after 100 km/h and 402 m; **Stop** cancels. A configuration that does not finish in 150 s is skipped. Needs a long flat straight such as Grid Map; each configuration takes about 30-40 s including loading.

Every result is written to `settings/perfbox_results.csv` in the BeamNG user folder and to the game log (tag `perfbox`), with the vehicle's mass for auto runs.

## Language

The texts follow the game's language: Russian when the game is in Russian, English otherwise. Translations: `locales/translations/<language>/perfbox.translation.json`. The CSV and the log are always in English.

## Files

- `lua/vehicle/extensions/perfboxVeh.lua`: the timer inside the vehicle (physics step) and the data for the UI.
- `lua/ge/extensions/perfbox.lua`: keeps the timer loaded in the player's vehicle, writes the CSV, runs the auto tests.
- `scripts/perfbox/modScript.lua`: loads the mod.
- `ui/modules/apps/PerfBox/`: the UI app.
- `locales/translations/`: English and Russian texts.
- `build.ps1`: packs `perfbox.zip` (`-Install` also copies it into the mods folder).

Check of the algorithm: at a constant 4 m/s² acceleration and 9 m/s² braking it matches the analytic values within 0.1 ms (0-100, 0-200, 1/4 and 1/2 mile, trap speed, 100-200, 100-0 and rollout).

---

## Русский

Замеры разгона, дистанции и торможения для BeamNG.drive, работает с любой машиной. Считает в шаге физики (2000 Гц) по времени симуляции, поэтому результат не зависит от FPS, частоты интерфейса и замедления времени.

- **Разгон с места:** 0-60, 0-60 mph, 0-100, 0-150, 0-200, 0-250, 0-300 км/ч и путь до этой скорости.
- **Дистанция:** 60 ft, 1/8, 1/4, 1/2 мили, 1 км, 1 миля и скорость на финише.
- **В движении:** 60-100, 80-120, 100-200, 200-300 км/ч.
- **Торможение:** 100-0 км/ч и тормозной путь.
- **Автозамер** (заводской старт с ручника полным газом) и **Все конфиги** (по очереди каждая конфигурация машины с одной точки).
- Окно сворачивается кнопкой «−». Результаты пишутся в `settings/perfbox_results.csv` и в лог игры.

**Установка через BeamNG.Earth:** Настройки → Add-ons → **Add from GitHub** → `yungdmize/PerfBox` → Install. Или вручную: `perfbox.zip` из [последнего релиза](../../releases/latest) в папку `mods`.

Язык выбирается по языку игры: русский, если игра на русском, иначе английский.
