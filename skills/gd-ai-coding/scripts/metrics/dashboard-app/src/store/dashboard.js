import { reactive, nextTick } from 'vue'

export const store = reactive({
  data: null,
  bindings: null,
  config: { vibeVisible: false },

  theme: 'light',

  activeTab: 'tab-overview',
  heroMeta: '',

  peopleViewMode: 'overview',
  selectedPersonEmail: null,
  peopleSortMode: 'activity',

  curPeopleViewMode: 'overview',
  selectedCurPersonName: null,

  versionViewMode: 'overview',
  selectedVersionKey: null,
  versionFilterText: '',
  versionScrollTarget: null,

  reqsViewMode: 'overview',
  selectedReqName: null,
  reqsFilterText: '',

  bindModalVisible: false,
  bindModalTraceReq: null,
  bindModalOwnerEmails: [],
  bindSelectedDdpReq: null,
  bindFilterText: '',

  deleteModalVisible: false,
  deleteTarget: null,

  remarks: {},
  remarkModalVisible: false,
  remarkModalReqName: null,
  remarkModalReqTitle: null,
  remarkModalDefaultAuthor: null,
  remarkModalAuthors: null,

  refreshButtonText: '↻ 刷新数据',
  refreshButtonColor: '',
  refreshDisabled: false,
  streamProgressVisible: false,
  streamProgressText: '',
  refreshTipVisible: false,
  refreshTipText: '',
  refreshTipColor: '',
})

export function setTheme(theme) {
  store.theme = theme
}

export function setActiveTab(tabId) {
  store.activeTab = tabId
}

export function setHeroMeta(text) {
  store.heroMeta = text
}

export function setData(data) {
  store.data = data
}

export function setBindings(bindings) {
  store.bindings = bindings
}

export function setConfig(config) {
  store.config = config
}

export function selectPerson(email) {
  store.selectedPersonEmail = email
  store.peopleViewMode = 'member'
}

export const selectPersonFromOverview = selectPerson

export function selectPeopleOverview() {
  store.peopleViewMode = 'overview'
}

export function togglePeopleSortMode() {
  store.peopleSortMode = store.peopleSortMode === 'activity' ? 'dac' : 'activity'
}

export function selectCurPerson(name) {
  store.selectedCurPersonName = name
  store.curPeopleViewMode = 'member'
}

export const selectCurPersonFromOverview = selectCurPerson

export function selectCurOverview() {
  store.curPeopleViewMode = 'overview'
}

export function selectVersion(versionKey) {
  store.selectedVersionKey = versionKey
  store.versionViewMode = 'detail'
}

export function selectVersionOverview() {
  store.versionViewMode = 'overview'
}

export function setVersionFilterText(text) {
  store.versionFilterText = text
}

export function setVersionScrollTarget(reqName) {
  store.versionScrollTarget = null
  nextTick(() => { store.versionScrollTarget = reqName })
}

export function selectReq(name) {
  store.selectedReqName = name
  store.reqsViewMode = 'detail'
}

export function selectReqsOverview() {
  store.reqsViewMode = 'overview'
}

export function setReqsFilterText(text) {
  store.reqsFilterText = text
}

export function showBindModal(traceReq, ownerEmails = []) {
  store.bindModalTraceReq = traceReq
  store.bindModalOwnerEmails = ownerEmails
  store.bindSelectedDdpReq = null
  store.bindFilterText = ''
  store.bindModalVisible = true
}

export function hideBindModal() {
  store.bindModalVisible = false
  store.bindModalTraceReq = null
  store.bindModalOwnerEmails = []
  store.bindSelectedDdpReq = null
  store.bindFilterText = ''
}

export function selectBindItem(ddpReq) {
  store.bindSelectedDdpReq = ddpReq
}

export function setBindFilterText(text) {
  store.bindFilterText = text
}

export function showDeleteModal(target) {
  store.deleteTarget = target
  store.deleteModalVisible = true
}

export function hideDeleteModal() {
  store.deleteModalVisible = false
  store.deleteTarget = null
}

export function setRefreshButton(text, color = '') {
  store.refreshButtonText = text
  store.refreshButtonColor = color
}

export function setRefreshDisabled(disabled) {
  store.refreshDisabled = disabled
}

export function setStreamProgress(text, visible = true) {
  store.streamProgressText = text
  store.streamProgressVisible = visible
}

export function setRemarks(remarks) {
  store.remarks = remarks || {}
}

export function showRemarkModal({ reqName, title = '', defaultAuthor = '', authors = null } = {}) {
  store.remarkModalReqName = reqName
  store.remarkModalReqTitle = title
  store.remarkModalDefaultAuthor = defaultAuthor
  // 填写人候选 = 该需求参与人姓名列表；缺省时弹窗回退为全团队 committers
  store.remarkModalAuthors = Array.isArray(authors) ? authors : null
  store.remarkModalVisible = true
}

export function hideRemarkModal() {
  store.remarkModalVisible = false
  store.remarkModalReqName = null
  store.remarkModalReqTitle = null
  store.remarkModalDefaultAuthor = null
  store.remarkModalAuthors = null
}

export function setRefreshTip(text, color = '', visible = true) {
  store.refreshTipText = text
  store.refreshTipColor = color
  store.refreshTipVisible = visible
}
