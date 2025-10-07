<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useAlert } from 'dashboard/composables';
import BaseBubble from './Base.vue';
import Button from 'next/button/Button.vue';
import Icon from 'next/icon/Icon.vue';
import { useSnakeCase } from 'dashboard/composables/useTransformKeys';
import { useMessageContext } from '../provider.js';
import GalleryView from 'dashboard/components/widgets/conversation/components/GalleryView.vue';
import { ATTACHMENT_TYPES } from '../constants';

const emit = defineEmits(['error']);
const { t } = useI18n();
const hasError = ref(false);
const showGallery = ref(false);
const isDownloading = ref(false);
const { filteredCurrentChatAttachments, attachments } = useMessageContext();

const handleError = () => {
  hasError.value = true;
  emit('error');
};

const attachment = computed(() => {
  return attachments.value[0];
});

const isReel = computed(() => {
  return attachment.value.fileType === ATTACHMENT_TYPES.IG_REEL;
});

const downloadVideo = async () => {
  const { fileType, dataUrl, extension } = attachment.value;
  
  try {
    isDownloading.value = true;
    
    // Create a temporary link element for direct download
    const link = document.createElement('a');
    link.href = dataUrl;
    link.download = `video.${extension || 'mp4'}`;
    link.rel = 'noreferrer noopener nofollow';
    
    // Append to body, click, and remove
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  } catch (error) {
    console.error('Download error:', error);
    useAlert(t('GALLERY_VIEW.ERROR_DOWNLOADING'));
  } finally {
    isDownloading.value = false;
  }
};
</script>

<template>
  <BaseBubble
    class="overflow-hidden p-3"
    data-bubble-name="video"
    @click="showGallery = true"
  >
    <div class="relative group rounded-lg overflow-hidden">
      <div
        v-if="isReel"
        class="absolute p-2 flex items-start justify-end right-0 pointer-events-none z-10"
      >
        <Icon icon="i-lucide-instagram" class="text-white shadow-lg" />
      </div>
      
      <!-- Download Button Overlay -->
      <div class="absolute top-2 left-2 opacity-0 group-hover:opacity-100 transition-opacity duration-200 z-20">
        <Button
          variant="ghost"
          size="sm"
          :disabled="isDownloading"
          @click.stop="downloadVideo"
          class="bg-n-slate-1/80 backdrop-blur-sm hover:bg-n-slate-1/90 text-n-slate-12 border border-n-slate-6"
        >
          <Icon 
            :icon="isDownloading ? 'i-lucide-loader-2' : 'i-lucide-download'" 
            :class="{ 'animate-spin': isDownloading }"
            class="w-4 h-4" 
          />
        </Button>
      </div>
      
      <video
        controls
        class="rounded-lg skip-context-menu"
        :src="attachment.dataUrl"
        :class="{
          'max-w-48': isReel,
          'max-w-full': !isReel,
        }"
        @error="handleError"
      />
    </div>
  </BaseBubble>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="useSnakeCase(attachment)"
    :all-attachments="filteredCurrentChatAttachments"
    @error="onError"
    @close="() => (showGallery = false)"
  />
</template>
