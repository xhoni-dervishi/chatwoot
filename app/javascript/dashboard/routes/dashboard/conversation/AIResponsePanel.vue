<script setup>
import { ref, computed, nextTick, onMounted } from 'vue';
import { useUISettings } from 'dashboard/composables/useUISettings';
import SidebarActionsHeader from 'dashboard/components-next/SidebarActionsHeader.vue';
import AIApi from 'dashboard/api/ai';
import AiChatAPI from 'dashboard/api/aiChat';
import { emitter } from 'shared/helpers/mitt';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import { useStore } from 'vuex';
import Icon from 'dashboard/components-next/icon/Icon.vue';

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
const messageInput = ref('');
const chatMessages = ref([]);
const chatContainer = ref(null);
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
    loadingDots.value = (loadingDots.value + 1) % 4;
  }, 500);
};

const draftReply = async () => {
  if (isGenerating.value) return;

  isGenerating.value = true;
  error.value = '';
  aiResponse.value = '';
  
  startLoadingAnimation();

  try {
    const response = await AIApi.generateResponse(props.conversationId, '');
    
    if (response.data.success) {
      aiResponse.value = response.data.response;
      
      chatMessages.value.push({
        id: `user-${Date.now()}`,
        role: 'user',
        content: 'Draft a reply',
        created_at: new Date().toISOString(),
      });
      
      chatMessages.value.push({
        id: `ai-${Date.now()}`,
        role: 'assistant',
        content: response.data.response,
        created_at: new Date().toISOString(),
      });
      
      await scrollToBottom();
    } else {
      error.value = response.data.error || 'Failed to generate AI response';
    }
  } catch (err) {
    console.error('API Error:', err);
    error.value = err.response?.data?.error || 'An error occurred while generating the response';
  } finally {
    isGenerating.value = false;
  }
};

const sendMessage = async () => {
  const message = (messageInput.value || '').toString().trim();
  if (!message || isGenerating.value) return;

  // Add user message to UI immediately
  chatMessages.value.push({
    id: `user-${Date.now()}`,
    role: 'user',
    content: message,
    created_at: new Date().toISOString(),
  });

  messageInput.value = '';
  await scrollToBottom();

  isGenerating.value = true;
  error.value = '';
  startLoadingAnimation();

  try {
    const response = await AiChatAPI.sendMessage(props.conversationId, message);
    
    if (response.data.success) {
      // Remove the temporary user message and add the real ones
      chatMessages.value.pop();
      chatMessages.value.push(response.data.user_message);
      chatMessages.value.push(response.data.ai_message);
      await scrollToBottom();
    } else {
      error.value = response.data.error || 'Failed to send message';
      chatMessages.value.pop();
    }
  } catch (err) {
    console.error('AI Chat API Error:', err);
    error.value = err.response?.data?.error || 'An error occurred while sending the message';
    chatMessages.value.pop();
  } finally {
    isGenerating.value = false;
  }
};

const clearHistory = async () => {
  try {
    const response = await AiChatAPI.clearHistory(props.conversationId);
    if (response.data.success) {
      chatMessages.value = [];
      aiResponse.value = '';
    } else {
      error.value = response.data.error || 'Failed to clear history';
    }
  } catch (err) {
    console.error('Clear History Error:', err);
    error.value = 'An error occurred while clearing history';
  }
};

const loadHistory = async () => {
  try {
    const response = await AiChatAPI.getHistory(props.conversationId);
    if (response.data.success) {
      chatMessages.value = response.data.messages;
      await scrollToBottom();
    }
  } catch (err) {
    console.error('Load History Error:', err);
    // Don't show error for loading history, just start with empty chat
  }
};

const sendDraft = async (messageContent) => {
  const content = messageContent || draftResponse.value;
  if (!content || !content.toString().trim()) return;
  
  try {
    await store.dispatch('createPendingMessageAndSend', {
      conversationId: props.conversationId,
      message: content,
      private: false, 
    });
    
  } catch (err) {
    console.error('Failed to send message:', err);
    error.value = 'Failed to send message. Please try again.';
  }
};

const copyToClipboard = async (messageContent) => {
  const content = messageContent || draftResponse.value;
  if (!content || !content.toString().trim()) return;
  
  try {
    await navigator.clipboard.writeText(content);
  } catch (err) {
    console.error('Failed to copy to clipboard:', err);
  }
};

const insertIntoEditor = (messageContent) => {
  const content = messageContent || draftResponse.value;
  if (!content || !content.toString().trim()) return;
  emitter.emit(BUS_EVENTS.INSERT_INTO_NORMAL_EDITOR, content);
};

const scrollToBottom = async () => {
  await nextTick();
  if (chatContainer.value) {
    chatContainer.value.scrollTop = chatContainer.value.scrollHeight;
  }
};

const handleKeyPress = (event) => {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault();
    sendMessage();
  }
};

const extractDraftResponse = (response) => {
  if (!response) return '';
  
  const draftResponseMatch = response.match(/###\s*Draft Response\s*\n([\s\S]*?)(?=\n###|$)/i);
  
  if (draftResponseMatch && draftResponseMatch[1]) {
    return draftResponseMatch[1]?.trim() || '';
  }
  
  return response;
};

const draftResponse = computed(() => extractDraftResponse(aiResponse.value));
const hasResponse = computed(() => aiResponse.value && aiResponse.value.length > 0);
const hasChatMessages = computed(() => chatMessages.value.length > 0);
const showEmptyState = computed(() => !hasResponse.value && !hasChatMessages.value && !isGenerating.value && !error.value);
const loadingText = computed(() => {
  const dots = '.'.repeat(loadingDots.value);
  return `AI is thinking${dots}`;
});

onMounted(() => {
  loadHistory();
});
</script>

<template>
  <div class="h-full w-full flex flex-col">
    <SidebarActionsHeader
      :title="$t('CONVERSATION.SIDEBAR.AI_RESPONSE')"
      @close="closeAIResponsePanel"
    />
    
    <!-- Header -->
    <div class="flex items-center gap-3 p-4 border-b border-n-weak flex-shrink-0">
      <div class="w-8 h-8 bg-n-brand rounded-full flex items-center justify-center">
        <Icon icon="i-lucide-bot" class="w-4 h-4 text-white" />
      </div>
      <div class="flex-1">
        <h3 class="text-sm font-medium text-n-slate-12">AI Assistant</h3>
        <p class="text-xs text-n-slate-10">Draft replies and chat with AI</p>
      </div>
      <button
        v-if="hasChatMessages"
        @click="clearHistory"
        class="p-1 text-n-slate-10 hover:text-n-slate-12 hover:bg-n-slate-4 rounded"
        :title="$t('CONVERSATION.SIDEBAR.CLEAR_CHAT')"
      >
        <Icon icon="i-lucide-trash-2" class="w-4 h-4" />
      </button>
    </div>

    <!-- Chat Area -->
    <div ref="chatContainer" class="flex-1 min-h-0 overflow-auto p-4 space-y-4">
      <!-- Chat Messages -->
      <div v-for="message in chatMessages" :key="message.id" class="flex items-start gap-3" :class="{ 'flex-row-reverse': message.role === 'user' }">
        <!-- User Message -->
        <div v-if="message.role === 'user'" class="flex-1 flex gap-3 items-start">
          <div class="bg-n-brand text-white rounded-lg p-3 ml-auto max-w-[calc(100%-88px)]">
            <p class="text-sm whitespace-pre-wrap">{{ message.content }}</p>
          </div>
          <div class="w-8 h-8 bg-n-brand rounded-full flex items-center justify-center flex-shrink-0">
            <Icon icon="i-lucide-user" class="w-4 h-4 text-white" />
          </div>
        </div>
        
        <!-- AI Message -->
        <div v-else class="flex items-start gap-3">
          <div class="w-8 h-8 bg-n-brand rounded-full flex items-center justify-center flex-shrink-0">
            <Icon icon="i-lucide-sparkles" class="w-4 h-4 text-white" />
          </div>
          <div class="bg-n-slate-4 rounded-lg p-3 max-w-[calc(100%-44px)]">
            <p class="text-sm text-n-slate-12 whitespace-pre-wrap">{{ message.content }}</p>
            <div v-if="message.content.includes('Draft Response')" class="flex gap-2 mt-2 border-t border-n-weak pt-2">
              <button
                @click="copyToClipboard(extractDraftResponse(message.content))"
                class="flex items-center gap-1 px-2 py-1 text-xs bg-n-slate-9/10 hover:bg-n-slate-9/20 rounded"
              >
                <Icon icon="i-lucide-copy" class="w-3 h-3" />
                Copy
              </button>
              <button
                @click="insertIntoEditor(extractDraftResponse(message.content))"
                class="flex items-center gap-1 px-2 py-1 text-xs bg-n-slate-9/10 hover:bg-n-slate-9/20 rounded"
              >
                <Icon icon="i-lucide-message-square" class="w-3 h-3" />
                Insert
              </button>
              <button
                @click="sendDraft(extractDraftResponse(message.content))"
                class="flex items-center gap-1 px-2 py-1 text-xs bg-n-brand text-white hover:brightness-110 rounded"
              >
                <Icon icon="i-lucide-send" class="w-3 h-3" />
                Send
              </button>
            </div>
          </div>
        </div>
      </div>

      <!-- Loading State -->
      <div v-if="isGenerating" class="flex items-start gap-3">
        <div class="w-8 h-8 bg-n-brand rounded-full flex items-center justify-center flex-shrink-0">
          <Icon icon="i-lucide-loader-pinwheel" class="w-4 h-4 text-white animate-spin" />
        </div>
        <div class="bg-n-slate-4 rounded-lg p-3">
          <p class="text-sm text-n-slate-10">{{ loadingText }}</p>
        </div>
      </div>

      <!-- Error State -->
      <div v-if="error" class="flex items-start gap-3">
        <div class="w-8 h-8 bg-red-500 rounded-full flex items-center justify-center flex-shrink-0">
          <Icon icon="i-lucide-alert-triangle" class="w-4 h-4 text-white" />
        </div>
        <div class="bg-red-50 rounded-lg p-3">
          <p class="text-sm text-red-800">{{ error }}</p>
        </div>
      </div>

      <!-- Empty State -->
      <div v-if="showEmptyState" class="flex flex-col items-center justify-center min-h-full text-center py-8">
        <div class="w-16 h-16 bg-n-slate-4 rounded-full flex items-center justify-center mb-4">
          <Icon icon="i-lucide-message-circle" class="w-8 h-8 text-n-slate-10" />
        </div>
        <h3 class="text-sm font-medium text-n-slate-12 mb-2">Start a conversation</h3>
        <p class="text-xs text-n-slate-10">Ask me anything about this conversation or request a draft reply</p>
      </div>
    </div>

    <!-- Footer -->
    <div class="border-t border-n-weak p-4 flex-shrink-0">
      <!-- Quick Actions -->
      <div class="mb-3">
        <button
          @click="draftReply"
          :disabled="isGenerating"
          class="flex items-center gap-2 px-3 py-2 bg-white border border-gray-300 rounded-lg text-sm font-medium text-gray-700 hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed"
        >
          <Icon icon="i-lucide-message-square" class="w-4 h-4 text-n-slate-12" />
          Draft a reply
        </button>
      </div>
      
      <!-- Chat Input -->
      <div class="flex gap-2">
        <textarea
          v-model="messageInput"
          @keydown="handleKeyPress"
          :disabled="isGenerating"
          placeholder="Ask me anything about this conversation..."
          class="flex-1 px-3 py-2 h-4 !mb-0 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
          rows="2"
        />
        <button
          @click="sendMessage"
          :disabled="isGenerating || !messageInput?.trim()"
          class="px-3 py-2 bg-n-brand text-white rounded-lg hover:brightness-110 disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center"
        >
          <Icon icon="i-lucide-send" class="w-4 h-4" />
        </button>
      </div>
    </div>
  </div>
</template>