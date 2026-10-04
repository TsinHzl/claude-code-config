import { describe, it, expect, beforeEach, vi } from 'vitest'
import { mount, flushPromises } from '@vue/test-utils'
import DeleteModal from '../components/modals/DeleteModal.vue'
import { store, showDeleteModal } from '../store/dashboard'
import { postDeleteTrace } from '../api/trace'
import { fetchData, fetchBindings } from '../api/data'

vi.mock('../api/trace', () => ({
  postDeleteTrace: vi.fn(),
}))
vi.mock('../api/data', () => ({
  fetchData: vi.fn(),
  fetchBindings: vi.fn(),
}))

describe('DeleteModal 删除 trace 记录', () => {
  beforeEach(() => {
    store.data = { committers: [], requirements_index: [] }
    store.bindings = { 'TRACE-1': 'REQ-1' }
    showDeleteModal({ committer: 'user-gamma', reqName: 'REQ-9' })
    postDeleteTrace.mockReset()
    fetchData.mockReset()
    fetchBindings.mockReset()
  })

  it('确认删除后立即刷新绑定与数据，无需等待下一次手动刷新', async () => {
    postDeleteTrace.mockResolvedValue(undefined)
    fetchBindings.mockResolvedValue({})
    fetchData.mockResolvedValue({ committers: [], requirements_index: [] })

    const wrapper = mount(DeleteModal, { attachTo: document.body })
    await wrapper.find('#delete-confirm').trigger('click')
    await flushPromises()

    expect(postDeleteTrace).toHaveBeenCalledWith('user-gamma', 'REQ-9')
    expect(store.deleteModalVisible).toBe(false)
    expect(fetchBindings).toHaveBeenCalled()
    expect(fetchData).toHaveBeenCalled()
    expect(store.bindings).toEqual({})
    expect(store.data).toEqual({ committers: [], requirements_index: [] })

    wrapper.unmount()
  })
})
