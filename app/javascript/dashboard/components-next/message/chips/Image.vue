<script setup>
import { ref } from 'vue';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../provider.js';
import { downloadFile } from 'dashboard/utils/downloadFile';

import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';

defineProps({
  attachment: {
    type: Object,
    required: true,
  },
});
const hasError = ref(false);
const showGallery = ref(false);

const { filteredCurrentChatAttachments } = useMessageContext();

const handleError = () => {
  hasError.value = true;
};

const downloadImage = async (event) => {
  event.stopPropagation(); // Prevent opening gallery
  const { fileType, dataUrl, extension } = attachment;
  
  try {
    await downloadFile({
      url: dataUrl,
      type: fileType,
      extension: extension,
    });
  } catch (error) {
    console.error('Download error:', error);
  }
};
</script>

<template>
  <div
    class="size-[72px] overflow-hidden contain-content rounded-xl cursor-pointer relative group"
    @click="showGallery = true"
  >
    <div
      v-if="hasError"
      class="flex flex-col items-center justify-center gap-1 text-xs text-center rounded-lg size-full bg-n-alpha-1 text-n-slate-11"
    >
      <Icon icon="i-lucide-circle-off" class="text-n-slate-11" />
      {{ $t('COMPONENTS.MEDIA.LOADING_FAILED') }}
    </div>
    <img
      v-else
      class="object-cover w-full h-full skip-context-menu"
      :src="attachment.dataUrl"
      @error="handleError"
    />
    <button
      v-if="!hasError"
      class="absolute top-1 right-1 p-1 bg-n-slate-1/80 backdrop-blur-sm rounded-full opacity-0 group-hover:opacity-100 transition-opacity duration-200 hover:bg-n-slate-2/80"
      @click="downloadImage"
    >
      <Icon icon="i-lucide-download" class="size-3 text-n-slate-12" />
    </button>
  </div>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="useSnakeCase(attachment)"
    :all-attachments="filteredCurrentChatAttachments"
    @error="handleError"
    @close="() => (showGallery = false)"
  />
</template>
