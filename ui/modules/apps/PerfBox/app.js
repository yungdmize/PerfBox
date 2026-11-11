angular.module('beamng.apps')
.directive('perfBox', ['$filter', function ($filter) {
  return {
    template: `
<div class="pbx" ng-class="{collapsed: collapsed}">
  <style>
    .pbx { width: 100%; height: 100%; display: flex; flex-direction: column; background: rgba(12, 14, 18, 0.88); color: #e8e8e8;
           font-family: "Roboto Mono", Consolas, monospace; font-size: 12px; box-sizing: border-box; padding: 6px 8px; overflow: hidden; }
    .pbx-head { display: flex; align-items: baseline; justify-content: space-between; }
    .pbx-speed { font-size: 34px; font-weight: bold; color: #fff; letter-spacing: 1px; }
    .pbx-speed span { font-size: 12px; color: #9aa; margin-left: 4px; font-weight: normal; }
    .pbx-status { font-size: 12px; padding: 2px 6px; border-radius: 3px; background: #333; color: #ccc; }
    .pbx-status.standing { background: #1d6b2a; color: #fff; }
    .pbx-status.run { background: #c25b00; color: #fff; }
    .pbx-live { display: flex; justify-content: space-between; color: #9aa; margin: 2px 0 6px 0; }
    .pbx-live b { color: #fff; font-weight: bold; }
    .pbx-table { flex: 1; overflow-y: auto; }
    .pbx-group { color: #ff8a2a; font-weight: bold; margin-top: 4px; border-bottom: 1px solid #444; display: flex; justify-content: space-between; }
    .pbx-group span { color: #777; font-weight: normal; }
    .pbx table { width: 100%; border-collapse: collapse; }
    .pbx td { padding: 1px 2px; white-space: nowrap; }
    .pbx td.t, .pbx td.x, .pbx td.b { text-align: right; }
    .pbx td.b { color: #8fd18f; }
    .pbx tr.stale td.t, .pbx tr.stale td.x { color: #777; }
    .pbx tr.fresh td.t { color: #ffb347; font-weight: bold; }
    .pbx-cols { color: #777; display: flex; justify-content: flex-end; gap: 0; margin-top: 2px; }
    .pbx-btns { display: flex; gap: 6px; margin-top: 6px; }
    .pbx-btns button { flex: 1; background: #2a2f38; color: #eee; border: 1px solid #555; border-radius: 3px; padding: 4px; cursor: pointer;
                       font-family: inherit; font-size: 12px; }
    .pbx-btns button.on { background: #c25b00; border-color: #ff8a2a; }
    .pbx-empty { color: #999; padding: 12px 0; text-align: center; }
    .pbx-sweep { color: #ffb347; margin-top: 4px; }
    .pbx-right { display: flex; align-items: center; gap: 6px; }
    .pbx-min { background: #2a2f38; color: #eee; border: 1px solid #555; border-radius: 3px; width: 22px; height: 20px; padding: 0;
               cursor: pointer; font-family: inherit; font-size: 14px; line-height: 16px; }
    .pbx.collapsed { height: auto; padding: 3px 6px; }
    .pbx.collapsed .pbx-speed { font-size: 20px; }
    .pbx-mini { display: flex; flex-wrap: wrap; gap: 0 10px; color: #9aa; }
    .pbx-mini b { color: #fff; }
    .pbx-mini b.fresh { color: #ffb347; }
  </style>
  <div class="pbx-head">
    <div class="pbx-speed">{{ fmtSpeed(d.kmh) }}<span>{{ 'perfbox.unit.kmh' | translate }}</span></div>
    <div class="pbx-right">
      <div class="pbx-status" ng-class="d ? d.mode : ''">{{ statusText() }}</div>
      <button class="pbx-min" ng-click="toggleCollapsed()" title="{{ (collapsed ? 'perfbox.expand' : 'perfbox.collapse') | translate }}">{{ collapsed ? '+' : '−' }}</button>
    </div>
  </div>
  <div class="pbx-mini" ng-if="collapsed">
    <div ng-repeat="m in miniKeys">{{ miniLabel(m) }} <b ng-class="{fresh: row(m.key).fresh}">{{ fmtT(row(m.key).t) }}</b></div>
  </div>
  <div class="pbx-sweep" ng-if="collapsed && sweep && !sweep.done">{{ sweep.i }}/{{ sweep.n }} {{ sweep.config }}</div>
  <div class="pbx-sweep" ng-if="collapsed && d && d.auto">{{ autoLine(d.auto) }}</div>
  <div class="pbx-live" ng-if="!collapsed">
    <div>{{ 'perfbox.live.time' | translate }} <b>{{ fmtT(d.runTime) }}</b></div>
    <div>{{ 'perfbox.live.dist' | translate }} <b>{{ fmtM(d.runDist) }}</b></div>
    <div>{{ 'perfbox.live.max' | translate }} <b>{{ fmtSpeed(d.maxKmh) }}</b></div>
  </div>
  <div class="pbx-table" ng-if="!collapsed">
    <div ng-if="!d" class="pbx-empty">{{ 'perfbox.empty' | translate }}</div>
    <div ng-repeat="g in d.groups track by $index">
      <div class="pbx-group">{{ groupName(g) }} <span>{{ groupColumns(g) }}</span></div>
      <table>
        <tr ng-repeat="r in g.rows track by r.key" ng-class="{fresh: r.fresh, stale: !r.fresh}">
          <td>{{ metricLabel(r) }}</td>
          <td class="t">{{ fmtT(r.t) }}</td>
          <td class="x">{{ fmtX(r.group, r.x) }}</td>
          <td class="b">{{ fmtT(r.bt) }}</td>
        </tr>
      </table>
    </div>
  </div>
  <div class="pbx-sweep" ng-if="!collapsed && sweep && !sweep.done">{{ sweepLine() }}</div>
  <div class="pbx-sweep" ng-if="!collapsed && d && d.auto">{{ autoLine(d.auto) }}</div>
  <div class="pbx-btns" ng-if="!collapsed">
    <button ng-class="{on: d && d.rollout}" ng-click="toggleRollout()">{{ rolloutText() }}</button>
    <button ng-click="reset()">{{ 'perfbox.reset' | translate }}</button>
  </div>
  <div class="pbx-btns" ng-if="!collapsed">
    <button ng-click="autoTest()" title="{{ 'perfbox.autoTest.hint' | translate }}">{{ 'perfbox.autoTest' | translate }}</button>
    <button ng-click="autoSweep()" title="{{ 'perfbox.autoSweep.hint' | translate }}">{{ 'perfbox.autoSweep' | translate }}</button>
    <button ng-click="stopAuto()">{{ 'perfbox.stop' | translate }}</button>
  </div>
</div>`,
    replace: true,
    restrict: 'EA',
    scope: true,
    link: function (scope, element, attrs) {
      // texts come from locales/translations/<lang>/perfbox.translation.json (en-US is the fallback)
      var tr = $filter('translate')
      scope.d = null

      // collapsed mode: one compact bar (speed, status, key results); remembered per browser profile
      var STORE_KEY = 'perfbox.collapsed'
      scope.collapsed = false
      try { scope.collapsed = window.localStorage.getItem(STORE_KEY) === '1' } catch (e) {}
      scope.toggleCollapsed = function () {
        scope.collapsed = !scope.collapsed
        try { window.localStorage.setItem(STORE_KEY, scope.collapsed ? '1' : '0') } catch (e) {}
      }
      scope.miniKeys = [
        {key: 's100', label: '0-100'},
        {key: 'i100_200', label: '100-200'},
        {key: 'd402', tkey: 'perfbox.mini.d402'},
      ]
      scope.miniLabel = function (m) { return m.tkey ? tr(m.tkey) : m.label }
      var noRow = {}
      scope.row = function (key) {
        if (!scope.d || !scope.d.groups) { return noRow }
        for (var g = 0; g < scope.d.groups.length; g++) {
          var rows = scope.d.groups[g].rows || []
          for (var i = 0; i < rows.length; i++) {
            if (rows[i].key === key) { return rows[i] }
          }
        }
        return noRow
      }

      scope.groupName = function (g) { return tr('perfbox.group.' + g.id) }
      scope.groupColumns = function (g) { return tr('perfbox.columns', {unit: tr('perfbox.groupUnit.' + g.id)}) }
      scope.metricLabel = function (r) {
        var key = 'perfbox.metric.' + r.key
        var text = tr(key)
        return text === key ? r.label : text
      }

      var has = function (v) { return v !== undefined && v !== null && !isNaN(v) }
      scope.fmtSpeed = function (k) { return has(k) ? k.toFixed(1) : '0.0' }
      scope.fmtT = function (t) { return has(t) ? t.toFixed(2) + ' ' + tr('perfbox.unit.s') : '—' }
      scope.fmtM = function (m) { return has(m) ? m.toFixed(1) + ' ' + tr('perfbox.unit.m') : '—' }
      scope.fmtX = function (group, x) {
        if (!has(x)) { return '' }
        return x.toFixed(1) + ' ' + tr(group === 'dist' ? 'perfbox.unit.kmh' : 'perfbox.unit.m')
      }
      scope.statusText = function () {
        if (!scope.d) { return tr('perfbox.status.none') }
        switch (scope.d.mode) {
          case 'standing': return tr('perfbox.status.standing')
          case 'run': return tr('perfbox.status.run')
          default: return tr('perfbox.status.moving')
        }
      }
      scope.rolloutText = function () {
        return tr('perfbox.rollout', {state: tr(scope.d && scope.d.rollout ? 'perfbox.on' : 'perfbox.off')})
      }

      var vehLua = function (cmd) {
        bngApi.activeObjectLua('if extensions.perfboxVeh then extensions.perfboxVeh.' + cmd + ' end')
      }
      scope.reset = function () { vehLua('reset()') }
      scope.toggleRollout = function () { vehLua('toggleRollout()') }
      scope.autoTest = function () { bngApi.engineLua('if perfbox then perfbox.autoTest() end') }
      scope.autoSweep = function () { bngApi.engineLua('if perfbox then perfbox.autoSweep() end') }
      scope.stopAuto = function () { bngApi.engineLua('if perfbox then perfbox.stopAuto() end') }
      scope.autoText = function (phase) {
        switch (phase) {
          case 'settle': return tr('perfbox.auto.settle')
          case 'launch': return tr('perfbox.auto.launch')
          case 'stop': return tr('perfbox.auto.stop')
          default: return phase
        }
      }
      scope.autoLine = function (phase) { return tr('perfbox.auto', {phase: scope.autoText(phase)}) }
      scope.sweep = null
      scope.sweepLine = function () {
        var s = scope.sweep
        if (!s) { return '' }
        return tr('perfbox.sweep', {i: s.i, n: s.n, config: s.config}) + (s.busy ? tr('perfbox.sweep.busy') : '')
      }

      scope.$on('PerfBoxUpdate', function (event, data) {
        scope.$evalAsync(function () { scope.d = data })
      })
      scope.$on('PerfBoxSweep', function (event, data) {
        scope.$evalAsync(function () { scope.sweep = data })
      })

      var attach = function () {
        bngApi.engineLua('if perfbox then perfbox.ensure() end')
        setTimeout(function () { vehLua('requestUI()') }, 300)
      }
      scope.$on('VehicleChange', attach)
      scope.$on('VehicleFocusChanged', attach)
      attach()
    }
  }
}])
