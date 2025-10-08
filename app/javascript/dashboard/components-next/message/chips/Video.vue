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

const showGallery = ref(false);

const { filteredCurrentChatAttachments } = useMessageContext();

const downloadVideo = async (event) => {
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
    <video
      :src="attachment.dataUrl"
      class="w-full h-full object-cover"
      muted
      playsInline
    />
    <div
      class="absolute w-full h-full inset-0 p-1 flex items-center justify-center"
    >
      <div
        class="size-7 bg-n-slate-1/60 backdrop-blur-sm rounded-full overflow-hidden shadow-[0_5px_15px_rgba(0,0,0,0.4)]"
      >
        <Icon
          icon="i-teenyicons-play-small-solid"
          class="size-7 text-n-slate-12/80 backdrop-blur"
        />
      </div>
    </div>
    <button
      class="absolute top-1 right-1 p-1 bg-n-slate-1/80 backdrop-blur-sm rounded-full opacity-0 group-hover:opacity-100 transition-opacity duration-200 hover:bg-n-slate-2/80"
      @click="downloadVideo"
    >
      <Icon icon="i-lucide-download" class="size-3 text-n-slate-12" />
    </button>
  </div>
  <GalleryView
    v-if="showGallery"
    v-model:show="showGallery"
    :attachment="useSnakeCase(attachment)"
    :all-attachments="filteredCurrentChatAttachments"
    @error="onError"
    @close="() => (showGallery = false)"
  />
</template>
