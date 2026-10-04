<template>
  <div v-if="ddp" class="ep-req-meta">
    <span v-if="ddp.state" class="ep-bd"><EpIcon name="tag" :size="9" />{{ ddp.state }}</span>
    <span v-if="ddp.expected_release && !ddp.release_version_name" class="ep-bd">
      <EpIcon name="calendar" :size="9" />{{ ddp.expected_release }}
    </span>
    <span v-if="ddp.release_version_name" class="ep-bd">
      <EpIcon name="rocket" :size="9" />{{ ddp.release_version_name }}{{ ddp.release_version_time ? ' · ' + ddp.release_version_time : '' }}
    </span>
  </div>
</template>

<script setup>
import EpIcon from './EpIcon.vue'

defineProps({
  ddp: { type: Object, default: null },
})
</script>
