#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

failures=()

fail() {
  failures+=("$1")
}

require_contains() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if ! grep -Fq "$pattern" "$file"; then
    fail "$file: missing required source contract: $description"
  fi
}

require_not_contains() {
  local file="$1"
  local pattern="$2"
  local description="$3"

  if grep -Fq "$pattern" "$file"; then
    fail "$file: forbidden source contract found: $description"
  fi
}

require_contains "Views/SettingsAppShell.swift" "SettingsNavigationGroup(title: \"核心\"" "settings core navigation group"
require_contains "Views/SettingsAppShell.swift" "SettingsNavigationGroup(title: \"自动化\"" "settings automation navigation group"
require_contains "Views/SettingsAppShell.swift" "SettingsNavigationGroup(title: \"系统\"" "settings system navigation group"
require_contains "Views/AppDesignSystem.swift" "0.961, green: 0.961, blue: 0.969" "approved settings background token"
require_contains "Views/AppDesignSystem.swift" "static let largeCard: CGFloat = 16" "approved large card radius"
require_contains "Views/AppDesignSystem.swift" "accessibilityReduceMotion" "settings reduce motion support"

require_contains "Views/SettingsRootView.swift" ".toggleStyle(SettingsSwitchToggleStyle())" "widget cards use settings switch style"
require_contains "Panel/SettingsWindowController.swift" "window.alphaValue = 0" "settings window hidden before first reveal"
require_contains "Panel/SettingsWindowController.swift" "revealWindowWhenActive" "settings window reveal gate"
require_contains "Panel/SettingsWindowController.swift" "window.isKeyWindow" "settings window key-window reveal check"

require_contains "Views/IslandShellLayout.swift" "case .imageCard:" "image card layout case"
require_contains "Views/IslandShellLayout.swift" "return 0.68" "image card compact width ratio"
require_contains "Views/IslandShellLayout.swift" "return 104" "image card minimum width"
require_contains "Views/IslandShellLayout.swift" "case .todo:" "todo layout case"
require_contains "Views/IslandShellLayout.swift" "return 0.92" "todo compact width ratio"
require_contains "Views/IslandShellLayout.swift" "return 188" "todo minimum width"
require_contains "Views/ExpandedIslandView.swift" "visibleItemCount: 3" "todo date selector uses three visible columns"
require_contains "Views/ExpandedIslandView.swift" ".frame(width: isCompact ? 9 : 10, height: isCompact ? 9 : 10)" "todo compact completion indicator"
require_contains "Views/ExpandedIslandView.swift" ".font(.system(size: isCompact ? 10.5 : 12" "todo compact row typography"
require_contains "Views/ExpandedIslandView.swift" ".font(.system(size: isCompact ? 11 : 13, weight: .semibold, design: .rounded))" "todo compact empty typography"
require_not_contains "Views/ExpandedIslandView.swift" ".id(dayIdentifier(for: effectiveSelectedDate)" "todo date changes must not recreate list preview"
require_not_contains "Views/ExpandedIslandView.swift" ".transition(.opacity.combined(with: .offset(y: 4)))" "todo date changes must not transition list preview"
require_contains "Views/ExpandedIslandView.swift" "NSEvent.addLocalMonitorForEvents" "todo floating panel outside click monitor"
require_contains "Views/ExpandedIslandView.swift" "event.window !== presentedPanel" "todo floating panel ignores own clicks"
require_contains "Views/ExpandedIslandView.swift" "removeOutsideClickMonitor()" "todo floating panel removes monitor"
require_contains "Views/ExpandedIslandView.swift" "DispatchQueue.main.async" "todo floating panel closes after click dispatch"
require_contains "Views/ExpandedIslandView.swift" "unifiedModuleCardBackground(shape: shape)" "module cards use unified background pipeline"
require_contains "Views/ExpandedIslandView.swift" "unifiedModuleCardBorder(shape)" "module cards use unified border pipeline"
require_not_contains "Views/ExpandedIslandView.swift" "weatherCardBorder(shape)" "weather-specific module border path"
require_not_contains "Views/ExpandedIslandView.swift" "todoScheduleCardBorder(shape)" "todo-specific module border path"
require_not_contains "Views/ExpandedIslandView.swift" "moduleAtmosphereStyle" "removed module atmosphere style"
require_not_contains "Views/ExpandedIslandView.swift" ".random(" "module visuals must be deterministic"

require_contains "Views/ExpandedIslandView.swift" "@ObservedObject var deviceInfoProvider: DeviceInfoProvider" "expanded view observes the shared device provider"
require_not_contains "Views/ExpandedIslandView.swift" "@StateObject private var deviceInfoProvider = DeviceInfoProvider()" "expanded view must not duplicate device sampling"
require_contains "Views/ExpandedIslandView.swift" "if settings.showCalendarModule" "calendar provider starts only when its module is enabled"
require_contains "Views/ExpandedIslandView.swift" "if settings.showTodoModule" "reminder provider starts only when its module is enabled"
require_contains "Views/IslandRootView.swift" "deviceInfoProvider: deviceInfoProvider" "root injects the shared device provider"
require_contains "Views/IslandRootView.swift" "refreshRuntimeProviders()" "root updates providers from visible requirements"
require_contains "Models/PlaybackProvider.swift" "if self.snapshot != enriched" "unchanged playback snapshots do not republish"
require_contains "Models/PlaybackProvider.swift" "if self.diagnosticText != result.diagnostic" "unchanged playback diagnostics do not republish"
require_contains "Models/WeatherProvider.swift" "geocoder.reverseGeocodeLocation(location)" "weather provider reuses its cancellable geocoder"
require_not_contains "Models/WeatherProvider.swift" "private static func placeName" "weather geocoder lookup is owned by the provider"
require_contains "Views/GridRevealScheduler.swift" "final class GridRevealScheduler" "shared grid reveal scheduler"
require_contains "Views/ApplicationsGridView.swift" "@StateObject private var revealScheduler = GridRevealScheduler()" "applications grid uses shared reveal scheduler"
require_contains "Views/FilesGridView.swift" "@StateObject private var revealScheduler = GridRevealScheduler()" "files grid uses shared reveal scheduler"

brand_paths=()
for path in App Models Panel Views docs design-qa.md; do
  if [[ -e "$path" ]]; then
    brand_paths+=("$path")
  fi
done

if ((${#brand_paths[@]} > 0)); then
  while IFS= read -r -d '' file; do
    if grep -Eq 'L-Nook|LNook|L_Nook' "$file"; then
      fail "$file: legacy brand name remains"
    fi
  done < <(
    find "${brand_paths[@]}" \
      -path "*/.build" -prune -o \
      -path "*/DerivedData" -prune -o \
      -type f \( -name "*.swift" -o -name "*.md" -o -name "*.json" \) -print0
  )
fi

require_not_contains "NookFlow.xcodeproj/project.pbxproj" "L-Nook" "legacy project brand L-Nook"
require_not_contains "NookFlow.xcodeproj/project.pbxproj" "LNook" "legacy project brand LNook"
require_not_contains "NookFlow.xcodeproj/project.pbxproj" "L_Nook" "legacy project brand L_Nook"
require_contains "NookFlow.xcodeproj/project.pbxproj" "NookFlow.app" "app product name"
require_contains "NookFlow.xcodeproj/project.pbxproj" "PRODUCT_NAME = NookFlow;" "build product name"

if ((${#failures[@]} > 0)); then
  printf 'Source contract lint failed:\n' >&2
  printf ' - %s\n' "${failures[@]}" >&2
  exit 1
fi

printf 'Source contract lint passed.\n'
