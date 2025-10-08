<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';

import { useMessageContext } from '../provider.js';
import { downloadFile } from 'dashboard/utils/downloadFile';
import BaseAttachmentBubble from './BaseAttachment.vue';
import FileIcon from 'next/icon/FileIcon.vue';

const { attachments } = useMessageContext();

const { t } = useI18n();

const url = computed(() => {
  return attachments.value[0].dataUrl;
});

const fileName = computed(() => {
  if (url.value) {
    const filename = url.value.substring(url.value.lastIndexOf('/') + 1);
    return filename || t('CONVERSATION.UNKNOWN_FILE_TYPE');
  }
  return t('CONVERSATION.UNKNOWN_FILE_TYPE');
});

const fileType = computed(() => {
  return fileName.value.split('.').pop();
});

const isDownloading = ref(false);

const downloadFileAttachment = async () => {
  const attachment = attachments.value[0];
  const { fileType: type, dataUrl, extension } = attachment;
  
  try {
    isDownloading.value = true;
    
    await downloadFile({
      url: dataUrl,
      type: type,
      extension: extension,
    });
  } catch (error) {
    console.error('Download error:', error);
  } finally {
    isDownloading.value = false;
  }
};
</script>

<template>
  <BaseAttachmentBubble
    icon="i-teenyicons-user-circle-solid"
    icon-bg-color="bg-n-alpha-3 dark:bg-n-alpha-white"
    sender-translation-key="CONVERSATION.SHARED_ATTACHMENT.FILE"
    :content="decodeURI(fileName)"
    :action="{
      onClick: downloadFileAttachment,
      label: isDownloading ? $t('CONVERSATION.DOWNLOADING') : $t('CONVERSATION.DOWNLOAD'),
    }"
  >
    <template #icon>
      <FileIcon :file-type="fileType" class="size-4" />
    </template>
  </BaseAttachmentBubble>
</template>
