import { test, expect } from '@playwright/test'

function buildFixture(count) {
  const committers = Array.from({ length: count }, (_, i) => ({
    committer: `people-${i}`,
    committer_name: `成员${i}`,
    requirements: [],
  }))
  return { committers, requirements_index: [] }
}

test.beforeEach(async ({ page }) => {
  await page.route('**/api/config', (route) => route.fulfill({ json: { vibeVisible: false } }))
  await page.route('**/api/bindings', (route) => route.fulfill({ json: {} }))
  await page.route('**/api/data', (route) => route.fulfill({ json: buildFixture(60) }))
  await page.route('**/api/stream', (route) => route.fulfill({ status: 404, body: '' }))
})

test('人员卡片点击后侧边栏自动滚动，使目标卡片进入可视区域', async ({ page }) => {
  await page.goto('/')

  await page.getByRole('button', { name: /人员视图/ }).click()

  const scroller = page.locator('#people-list .ep-list-body')

  // 列表首项是「团队概览」入口，其后才是 60 个成员项
  const items = page.locator('#people-list .ep-li')
  await expect(items).toHaveCount(61)

  const targetIdx = 56
  const target = items.nth(targetIdx)

  // 点击前保持默认滚动位置（顶部），目标卡片在可视区域之外
  // 滚动容器是 .ep-list-body（#people-list 自身 overflow:hidden）
  await scroller.evaluate((el) => { el.scrollTop = 0 })
  // 用 dispatchEvent 而非 .click()：Playwright 的 .click() 会自动把目标滚入视口再点击，
  // 这里要验证的正是"点击后由应用自身的 scrollIntoView 完成定位"，不能被工具的自动滚动掩盖
  await target.dispatchEvent('click')

  await expect(target).toHaveClass(/(^|\s)sel(\s|$)/)

  await expect.poll(async () => {
    const sidebarBox = await scroller.boundingBox()
    const itemBox = await target.boundingBox()
    if (!sidebarBox || !itemBox) return false
    return itemBox.y >= sidebarBox.y - 1 && (itemBox.y + itemBox.height) <= (sidebarBox.y + sidebarBox.height) + 1
  }, { timeout: 2000 }).toBe(true)
})
