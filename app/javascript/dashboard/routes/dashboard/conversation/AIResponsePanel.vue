<script setup>
import { ref, computed } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import SidebarActionsHeader from 'dashboard/components-next/SidebarActionsHeader.vue';
import AIApi from 'dashboard/api/ai';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useStore } from 'vuex';

const props = defineProps({
  conversationId: {
    type: [Number, String],
    required: true,
  },
});

const { updateUISettings } = useUISettings();
const store = useStore();

const isGenerating = ref(false);
const aiResponse = ref('');
const error = ref('');
const customPrompt = ref('');
const loadingDots = ref(0);

const closeAIResponsePanel = () => {
  updateUISettings({
    is_ai_response_panel_open: false,
  });
};

const startLoadingAnimation = () => {
  loadingDots.value = 0;
  const interval = setInterval(() => {
    if (!isGenerating.value) {
      clearInterval(interval);
      return;
    }
    loadingDots.value = (loadingDots.value + 1) % 4; // 0, 1, 2, 3, then back to 0
  }, 500); // Change every 500ms
};

const draftReply = async () => {
  if (isGenerating.value) return;

  isGenerating.value = true;
  error.value = '';
  aiResponse.value = '';
  
  startLoadingAnimation();

  try {
    const prompt = customPrompt.value.trim();
    const response = await AIApi.generateResponse(props.conversationId, prompt);
    
    if (response.data.success) {
      aiResponse.value = response.data.response;
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

const sendDraft = async () => {
  if (!draftResponse.value.trim()) return;
  
  try {
    await store.dispatch('createPendingMessageAndSend', {
      conversationId: props.conversationId,
      message: draftResponse.value,
      private: false, 
    });
    
  } catch (err) {
    console.error('Failed to send message:', err);
    error.value = 'Failed to send message. Please try again.';
  }
};

const copyToClipboard = async () => {
  if (!draftResponse.value) return;
  
  try {
    await navigator.clipboard.writeText(draftResponse.value);
    console.log('Response copied to clipboard');
  } catch (err) {
    console.error('Failed to copy to clipboard:', err);
  }
};

const insertIntoEditor = () => {
  if (!draftResponse.value) return;
  emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, draftResponse.value);
};

const clearDraft = () => {
  aiResponse.value = '';
  customPrompt.value = '';
};

const extractDraftResponse = (response) => {
  if (!response) return '';
  
  const draftResponseMatch = response.match(/###\s*Draft Response\s*\n([\s\S]*?)(?=\n###|$)/i);
  
  if (draftResponseMatch && draftResponseMatch[1]) {
    return draftResponseMatch[1].trim();
  }
  
  return response;
};

const draftResponse = computed(() => extractDraftResponse(aiResponse.value));

const hasResponse = computed(() => aiResponse.value && aiResponse.value.length > 0);
const showEmptyState = computed(() => !hasResponse.value && !isGenerating.value && !error.value);
const loadingText = computed(() => {
  const dots = '.'.repeat(loadingDots.value);
  return `Drafting your reply${dots}`;
});
</script>

<template>
  <div class="bg-n-background h-full overflow-hidden flex flex-col fixed top-0 z-40 w-full max-w-sm transition-transform duration-300 ease-in-out ltr:right-0 rtl:left-0 md:static md:w-[320px] md:min-w-[320px] ltr:border-l rtl:border-r border-n-weak 2xl:min-w-[420px] 2xl:w-[420px] shadow-lg md:shadow-none md:flex">
    <SidebarActionsHeader
      :title="$t('CONVERSATION.SIDEBAR.AI_RESPONSE')"
      @close="closeAIResponsePanel"
    />
    
    <div class="flex flex-col h-full p-4 overflow-auto">
      <!-- Main Content Area -->
      <div class="flex-1 flex flex-col gap-4">
        <!-- Empty State - Show Draft Button -->
        <div v-if="showEmptyState" class="flex-1 flex flex-col items-center justify-end text-center mb-4">
          <div class="mb-6">
            <h3 class="text-lg font-medium text-gray-900 mb-2">AI Assistant</h3>
            <p class="text-sm text-gray-500 mb-6">Get AI-powered help drafting responses to your customers</p>
          </div>
          
          <!-- Custom Prompt Input (Optional) -->
          <div class="w-full mb-2">
            <label class="block text-xs font-medium text-n-slate-11 mb-2">
              Custom Prompt (Optional)
            </label>
            <textarea
              v-model="customPrompt"
              placeholder="Optional custom prompt for the AI to generate a response"
              class="w-full px-3 py-2 text-sm border border-n-weak rounded-lg resize-none focus:outline-none focus:ring-2 focus:ring-n-brand focus:border-transparent"
              rows="2"
            ></textarea>
          </div>
          
          <!-- Draft Reply Button -->
          <button
            @click="draftReply"
            :disabled="isGenerating"
            class="w-full px-6 py-3 bg-n-brand text-white rounded-lg font-medium disabled:opacity-50 disabled:cursor-not-allowed"
          >
            {{ isGenerating ? 'Drafting...' : 'Draft a reply' }}
          </button>
        </div>

        <!-- Loading State -->
        <div v-else-if="isGenerating" class="flex-1 flex flex-col items-center justify-center text-center">
          <h3 class="text-lg font-medium text-gray-900 mb-2">{{ loadingText }}</h3>
          <p class="text-sm text-gray-500">AI is analyzing the conversation and crafting a response</p>
        </div>

        <!-- Draft Display -->
        <div v-else-if="hasResponse" class="flex-1 flex flex-col items-center">
          <div class="mb-4">
            <div class="flex items-center justify-between mb-3">
              <h3 class="text-sm font-medium text-gray-900">AI Draft</h3>
              <button
                @click="clearDraft"
                class="text-xs text-gray-500 hover:text-gray-700"
              >
                Clear
              </button>
            </div>
            
            <!-- Draft Content -->
            <div class="w-full p-4 bg-gray-400 rounded">
              <p class="text-sm whitespace-pre-wrap">{{ aiResponse }}</p>
            </div>
          </div>

          <!-- Action Buttons -->
          <div class="space-y-3 w-full mt-auto">
            <button
              @click="sendDraft"
              class="w-full px-4 py-2 bg-n-brand text-white rounded-lg font-medium"
            >
              Send
            </button>
            
            <div class="flex space-x-2">
              <button
                @click="copyToClipboard"
                class="flex-1 px-4 py-2 bg-n-slate-9/10 text-n-slate-12 rounded-lg font-medium"
              >
                Copy
              </button>
              <button
                @click="insertIntoEditor"
                class="flex-1 px-4 py-2 bg-n-slate-9/10 text-n-slate-12 rounded-lg font-medium"
              >
                Insert
              </button>
            </div>
            
            <button
              @click="draftReply"
              :disabled="isGenerating"
              class="w-full px-4 py-2 border border-n-slate-9/10 text-n-slate-12 rounded-lg font-medium disabled:opacity-50"
            >
              Draft Another Reply
            </button>
          </div>
        </div>

        <!-- Error State -->
        <div v-else-if="error" class="flex-1 flex flex-col items-center justify-center text-center">
          <h3 class="text-lg font-medium text-gray-900 mb-2">Something went wrong</h3>
          <p class="text-sm text-n-slate-12 mb-6">{{ error }}</p>
          <button
            @click="draftReply"
            class="px-6 py-3 bg-n-brand text-white rounded-lg font-medium"
          >
            Try Again
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
