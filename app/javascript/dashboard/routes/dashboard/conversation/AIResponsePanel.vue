<script setup>
import { ref, computed } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import SidebarActionsHeader from 'dashboard/components-next/SidebarActionsHeader.vue';
import AIApi from 'dashboard/api/ai';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const { updateUISettings } = useUISettings();

const isGenerating = ref(false);
const aiResponse = ref('');
const error = ref('');
const customPrompt = ref('');

const closeAIResponsePanel = () => {
  updateUISettings({
    is_ai_response_panel_open: false,
  });
};

const generateResponse = async () => {
  console.log('Generating AI response for conversation:', props.conversationId);
  isGenerating.value = true;
  error.value = '';
  aiResponse.value = '';
  
  try {
    const response = await AIApi.generateResponse(props.conversationId, customPrompt.value);
    
    if (response.data.success) {
      // Extract the text from the response structure
      const messageContent = response.data.response.find(item => item.type === 'message');
      if (messageContent && messageContent.content && messageContent.content[0]) {
        aiResponse.value = messageContent.content[0].text;
      } else {
        aiResponse.value = 'No response text found in the API response.';
      }
    } else {
      error.value = response.data.error || 'Failed to generate AI response';
    }
  } catch (err) {
    console.error('API Error:', err);
    console.error('Error response:', err.response);
    error.value = err.response?.data?.error || 'An error occurred while generating the response';
  } finally {
    isGenerating.value = false;
  }
};

const hasResponse = computed(() => aiResponse.value && aiResponse.value.length > 0);
const showEmptyState = computed(() => !hasResponse.value && !isGenerating.value && !error.value);

const copyToClipboard = async () => {
  if (!aiResponse.value) return;
  
  try {
    await navigator.clipboard.writeText(aiResponse.value);
    console.log('Response copied to clipboard');
  } catch (err) {
    console.error('Failed to copy to clipboard:', err);
  }
};

const insertIntoEditor = () => {
  if (!aiResponse.value) return;
  emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, aiResponse.value);
  console.log('Response inserted into editor');
};
</script>

<template>
  <div class="bg-n-background h-full overflow-hidden flex flex-col fixed top-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out ltr:right-0 rtl:left-0 md:static md:w-[320px] md:min-w-[320px] ltr:border-l rtl:border-r border-n-weak 2xl:min-w-[420px] 2xl:w-[420px] shadow-lg md:shadow-none md:flex">
    <SidebarActionsHeader
      :title="$t('CONVERSATION.SIDEBAR.AI_RESPONSE')"
      @close="closeAIResponsePanel"
    />
    
    <div class="flex flex-col h-full p-4 overflow-auto">
      <!-- Simple Test -->
      <div class="flex-1 flex flex-col gap-4">
        <!-- Show response if available -->
        <div v-if="aiResponse" class="w-full p-4 bg-gray-400 rounded">
          <p class="text-sm">{{ aiResponse }}</p>
        </div>
        
        <!-- Show error if available -->
        <div v-if="error" class="w-full mt-4 p-4 bg-red-100 rounded">
          <p class="text-sm text-red-600">{{ error }}</p>
        </div>
       </div>
       
       <!-- Text Editor at Bottom -->
       <div class="mt-4">
         <label class="block text-xs font-medium text-n-slate-11 mb-2">
           Custom Prompt
         </label>
         <textarea
           v-model="customPrompt"
           placeholder="Add additional context or instructions..."
           class="w-full px-3 py-2 text-sm border border-n-weak rounded-lg resize-none focus:outline-none focus:ring-2 focus:ring-n-brand focus:border-transparent"
           rows="3"
         ></textarea>
         <div class="flex gap-2 mt-2">
         <button
           @click="copyToClipboard"
           :disabled="isGenerating"
           class="px-4 py-2 bg-n-brand text-white rounded-lg disabled:opacity-50 flex-1"
         >
           Copy Response
         </button>
         <button
          @click="generateResponse"
          :disabled="isGenerating"
          class="px-4 py-2 bg-n-brand text-white rounded-lg disabled:opacity-50 flex-1"
        >
          {{ isGenerating ? 'Generating...' : 'Generate Response' }}
        </button>
        <button
          @click="insertIntoEditor"
          :disabled="isGenerating"
          class="px-4 py-2 bg-n-brand text-white rounded-lg disabled:opacity-50 flex-1"
        >
          Insert into Editor
        </button>
        </div>
       </div>
     </div>
   </div>
 </template>
