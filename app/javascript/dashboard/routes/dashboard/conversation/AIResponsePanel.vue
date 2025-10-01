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
// Remove FollowUpScheduler import - we'll integrate it into the chat flow

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
const isInFollowUpMode = ref(false);
const currentFollowUp = ref(null);

const closeAIResponsePanel = () => {
  updateUISettings({
    is_ai_response_panel_open: false,
  });
};

const startFollowUpFlow = async () => {
  if (isInFollowUpMode.value) {
    // Cancel follow-up mode
    isInFollowUpMode.value = false;
    currentFollowUp.value = null;
    return;
  }

  // Add user message
  chatMessages.value.push({
    id: `followup-request-${Date.now()}`,
    role: 'user',
    content: 'Schedule a follow-up',
    created_at: new Date().toISOString(),
  });

  isInFollowUpMode.value = true;
  isGenerating.value = true;
  startLoadingAnimation();

  try {
    // First check for existing pending follow-ups
    const existingResponse = await AiChatAPI.getExistingFollowups(props.conversationId);
    
    if (existingResponse.data.success && existingResponse.data.followups.length > 0) {
      // Show existing follow-up and ask if user wants to change it
      const existingFollowup = existingResponse.data.followups[0]; // Only one pending at a time
      
      chatMessages.value.push({
        id: `followup-existing-${Date.now()}`,
        role: 'assistant',
        content: `You already have a pending follow-up:\n\n"${existingFollowup.message_content}"\n\nScheduled for: ${new Date(existingFollowup.scheduled_at).toLocaleString()}\n\nWould you like to change it?`,
        created_at: new Date().toISOString(),
        followUpData: {
          type: 'existing_followup_change',
          existingFollowup: existingFollowup
        }
      });
    } else {
      // No existing follow-up, start normal flow
      const response = await AiChatAPI.scheduleFollowup(props.conversationId);
      
      if (response.data.success) {
        if (response.data.should_followup) {
          // Add AI response with draft message and confirm button
          chatMessages.value.push({
            id: `followup-draft-${Date.now()}`,
            role: 'assistant',
            content: `I suggest this follow-up message:\n\n"${response.data.draft_message}"\n\nWould you like to proceed with this message?`,
            created_at: new Date().toISOString(),
            followUpData: {
              type: 'draft_confirmation',
              draftMessage: response.data.draft_message,
              suggestedTime: response.data.suggested_time,
              reasoning: response.data.reasoning
            }
          });
        } else {
          // No follow-up needed
          chatMessages.value.push({
            id: `followup-no-need-${Date.now()}`,
            role: 'assistant',
            content: response.data.reason,
            created_at: new Date().toISOString(),
          });
          isInFollowUpMode.value = false;
        }
      } else {
        chatMessages.value.push({
          id: `followup-error-${Date.now()}`,
          role: 'assistant',
          content: `Error: ${response.data.error}`,
          created_at: new Date().toISOString(),
        });
        isInFollowUpMode.value = false;
      }
    }
  } catch (err) {
    chatMessages.value.push({
      id: `followup-error-${Date.now()}`,
      role: 'assistant',
      content: `Error: ${err.response?.data?.error || 'An error occurred while checking for follow-ups'}`,
      created_at: new Date().toISOString(),
    });
    isInFollowUpMode.value = false;
  } finally {
    isGenerating.value = false;
    nextTick(() => scrollToBottom());
  }
};

const confirmDraftMessage = async (messageId) => {
  const message = chatMessages.value.find(m => m.id === messageId);
  if (!message?.followUpData) return;

  isGenerating.value = true;
  startLoadingAnimation();

  try {
    // Check if this is updating an existing follow-up
    const existingFollowupId = message.followUpData.existingFollowupId;
    
    if (existingFollowupId) {
      // Update existing follow-up
      const response = await AiChatAPI.updateFollowupDraft(
        props.conversationId,
        existingFollowupId,
        message.followUpData.draftMessage
      );

      if (response.data.success) {
        currentFollowUp.value = response.data.scheduled_followup;
        
        // Add AI response with time options
        chatMessages.value.push({
          id: `followup-time-${Date.now()}`,
          role: 'assistant',
          content: `Great! I've updated the follow-up message. It's scheduled for ${new Date(response.data.scheduled_followup.scheduled_at).toLocaleString()}. Would you like to change the timing?`,
          created_at: new Date().toISOString(),
          followUpData: {
            type: 'time_confirmation',
            followUpId: response.data.scheduled_followup.id,
            scheduledTime: response.data.scheduled_followup.scheduled_at
          }
        });
      } else {
        chatMessages.value.push({
          id: `followup-error-${Date.now()}`,
          role: 'assistant',
          content: `Error: ${response.data.error}`,
          created_at: new Date().toISOString(),
        });
      }
    } else {
      // Store the draft in currentFollowUp without creating in database yet
      currentFollowUp.value = {
        message: message.followUpData.draftMessage,
        scheduledTime: message.followUpData.suggestedTime,
        id: null // Not created in database yet
      };
      
      // Add AI response with time options
      console.log('Setting up time editing with data:', {
        draftMessage: message.followUpData.draftMessage,
        suggestedTime: message.followUpData.suggestedTime,
        followUpData: message.followUpData
      });
      
      chatMessages.value.push({
        id: `followup-time-${Date.now()}`,
        role: 'assistant',
        content: `Great! Now let's set the timing. When would you like to send this follow-up?\n\nI suggest ${new Date(message.followUpData.suggestedTime).toLocaleString()}, but you can tell me a different time like "10 minutes from now" or "tomorrow morning".`,
        created_at: new Date().toISOString(),
        followUpData: {
          type: 'time_editing',
          currentMessage: message.followUpData.draftMessage,
          currentTime: message.followUpData.suggestedTime,
          existingFollowupId: null
        }
      });
    }
  } catch (err) {
    chatMessages.value.push({
      id: `followup-error-${Date.now()}`,
      role: 'assistant',
      content: `Error: ${err.response?.data?.error || 'An error occurred while creating/updating the follow-up'}`,
      created_at: new Date().toISOString(),
    });
  } finally {
    isGenerating.value = false;
    nextTick(() => scrollToBottom());
  }
};

const proceedToTimeSelection = async (messageId) => {
  const message = chatMessages.value.find(m => m.id === messageId);
  if (!message?.followUpData) return;

  // Add AI response with time options
  chatMessages.value.push({
    id: `followup-time-${Date.now()}`,
    role: 'assistant',
    content: `Perfect! Now let's set the timing. When would you like to send this follow-up?\n\nI suggest 24 hours from now, but you can tell me a different time like "10 minutes from now" or "tomorrow morning".`,
    created_at: new Date().toISOString(),
    followUpData: {
      type: 'time_editing',
      currentMessage: message.followUpData.currentMessage,
      currentTime: message.followUpData.currentTime,
      existingFollowupId: message.followUpData.existingFollowupId || null
    }
  });

  nextTick(() => scrollToBottom());
};

const confirmTimeSelection = async (messageId) => {
  const message = chatMessages.value.find(m => m.id === messageId);
  if (!message?.followUpData) return;

  console.log('confirmTimeSelection called with message:', {
    messageId,
    followUpData: message.followUpData,
    draftMessage: message.followUpData.draftMessage,
    scheduledTime: message.followUpData.scheduledTime
  });

  isGenerating.value = true;
  startLoadingAnimation();

  try {
    // Check for existing follow-ups before final confirmation
    const existingResponse = await AiChatAPI.getExistingFollowups(props.conversationId);
    
    if (existingResponse.data.success && existingResponse.data.followups.length > 0) {
      // Show existing follow-ups with delete/replace options
      const followups = existingResponse.data.followups;
      let content = `I found ${followups.length} existing follow-up${followups.length > 1 ? 's' : ''}:\n\n`;
      
      followups.forEach((followup, index) => {
        content += `${index + 1}. "${followup.message_content}" - Scheduled for ${new Date(followup.scheduled_at).toLocaleString()}\n`;
      });
      
      content += `\nWould you like to replace the existing follow-up${followups.length > 1 ? 's' : ''} with this new one?`;

      // Get the message content from the appropriate field based on message type
      let messageContent = message.followUpData.draftMessage || message.followUpData.currentMessage;
      const scheduledTime = message.followUpData.scheduledTime || message.followUpData.currentTime;

      // If we still don't have message content (for time_confirmation type), get it from previous message
      if (!messageContent && message.followUpData.type === 'time_confirmation') {
        const previousMessage = chatMessages.value.find(m => 
          m.followUpData?.type === 'time_editing' && 
          chatMessages.value.indexOf(m) < chatMessages.value.indexOf(message)
        );
        if (previousMessage) {
          messageContent = previousMessage.followUpData.currentMessage;
        }
      }

      console.log('Creating newFollowup object with:', {
        message: messageContent,
        scheduledTime: scheduledTime,
        followUpId: message.followUpData.followUpId,
        messageType: message.followUpData.type
      });

      chatMessages.value.push({
        id: `followup-existing-check-${Date.now()}`,
        role: 'assistant',
        content: content,
        created_at: new Date().toISOString(),
        followUpData: {
          type: 'existing_followups_confirmation',
          existingFollowups: followups,
          newFollowup: {
            message: messageContent,
            scheduledTime: scheduledTime,
            followUpId: message.followUpData.followUpId
          }
        }
      });
    } else {
      // No existing follow-ups, create the new follow-up
      let messageContent = message.followUpData.draftMessage || message.followUpData.currentMessage;
      const scheduledTime = message.followUpData.scheduledTime || message.followUpData.currentTime;

      // If we still don't have message content (for time_confirmation type), get it from previous message
      if (!messageContent && message.followUpData.type === 'time_confirmation') {
        const previousMessage = chatMessages.value.find(m => 
          m.followUpData?.type === 'time_editing' && 
          chatMessages.value.indexOf(m) < chatMessages.value.indexOf(message)
        );
        if (previousMessage) {
          messageContent = previousMessage.followUpData.currentMessage;
        }
      }

      console.log('Creating follow-up with data:', {
        conversationId: props.conversationId,
        messageContent: messageContent,
        scheduledTime: scheduledTime,
        followUpData: message.followUpData
      });
      
      const response = await AiChatAPI.createFollowup(
        props.conversationId,
        messageContent,
        scheduledTime
      );

      if (response.data.success) {
        currentFollowUp.value = response.data.scheduled_followup;
        
        chatMessages.value.push({
          id: `followup-confirmed-${Date.now()}`,
          role: 'assistant',
          content: `✅ Perfect! Your follow-up has been scheduled successfully. I'll send the message at ${new Date(scheduledTime).toLocaleString()}.`,
          created_at: new Date().toISOString(),
        });

        isInFollowUpMode.value = false;
        currentFollowUp.value = null;
      } else {
        chatMessages.value.push({
          id: `followup-error-${Date.now()}`,
          role: 'assistant',
          content: `Error: ${response.data.error}`,
          created_at: new Date().toISOString(),
        });
      }
    }
  } catch (err) {
    console.log('Error checking existing follow-ups:', err);
    // Continue with final confirmation if check fails
    chatMessages.value.push({
      id: `followup-confirmed-${Date.now()}`,
      role: 'assistant',
      content: `✅ Perfect! Your follow-up has been scheduled successfully. I'll send the message at ${new Date(message.followUpData.currentTime || message.followUpData.scheduledTime).toLocaleString()}.`,
      created_at: new Date().toISOString(),
    });

    isInFollowUpMode.value = false;
    currentFollowUp.value = null;
  } finally {
    isGenerating.value = false;
    nextTick(() => scrollToBottom());
  }
};

const editDraftMessage = async (messageId, editRequest) => {
  const message = chatMessages.value.find(m => m.id === messageId);
  if (!message?.followUpData) return;

  isGenerating.value = true;
  startLoadingAnimation();

  try {
    // Use AI to update the draft
    const aiResponse = await AiChatAPI.sendMessage(
      props.conversationId,
      `Please update this follow-up message: "${message.followUpData.draftMessage}" based on this request: "${editRequest}". Return only the updated message.`
    );

    if (aiResponse.data.success) {
      const updatedMessage = aiResponse.data.ai_message.content;
      
      // Update the message with new draft
      message.followUpData.draftMessage = updatedMessage;
      message.content = `I've updated the follow-up message:\n\n"${updatedMessage}"\n\nWould you like to proceed with this message?`;
    } else {
      chatMessages.value.push({
        id: `followup-error-${Date.now()}`,
        role: 'assistant',
        content: `Error updating draft: ${aiResponse.data.error}`,
        created_at: new Date().toISOString(),
      });
    }
  } catch (err) {
    chatMessages.value.push({
      id: `followup-error-${Date.now()}`,
      role: 'assistant',
      content: `Error updating draft: ${err.response?.data?.error || 'An error occurred while updating the draft'}`,
      created_at: new Date().toISOString(),
    });
  } finally {
    isGenerating.value = false;
    nextTick(() => scrollToBottom());
  }
};

const replaceExistingFollowups = async (messageId) => {
  const message = chatMessages.value.find(m => m.id === messageId);
  if (!message?.followUpData) return;

  console.log('replaceExistingFollowups called with:', {
    messageId,
    followUpData: message.followUpData,
    newFollowup: message.followUpData.newFollowup
  });

  isGenerating.value = true;
  startLoadingAnimation();

  try {
    // Cancel all existing follow-ups
    const existingFollowups = message.followUpData.existingFollowups;
    for (const followup of existingFollowups) {
      try {
        await AiChatAPI.cancelFollowup(props.conversationId, followup.id);
      } catch (err) {
        console.log(`Could not cancel follow-up ${followup.id}:`, err);
      }
    }

    // Create the new follow-up
    console.log('Creating new follow-up with:', {
      conversationId: props.conversationId,
      message: message.followUpData.newFollowup.message,
      scheduledTime: message.followUpData.newFollowup.scheduledTime
    });

    const response = await AiChatAPI.createFollowup(
      props.conversationId,
      message.followUpData.newFollowup.message,
      message.followUpData.newFollowup.scheduledTime
    );

    if (response.data.success) {
      currentFollowUp.value = response.data.scheduled_followup;
      
      // Add final confirmation message
      chatMessages.value.push({
        id: `followup-confirmed-${Date.now()}`,
        role: 'assistant',
        content: `✅ Perfect! I've replaced the existing follow-up${existingFollowups.length > 1 ? 's' : ''} with your new one. Your follow-up has been scheduled successfully for ${new Date(message.followUpData.newFollowup.scheduledTime).toLocaleString()}.`,
        created_at: new Date().toISOString(),
      });

      isInFollowUpMode.value = false;
      currentFollowUp.value = null;
    } else {
      chatMessages.value.push({
        id: `followup-error-${Date.now()}`,
        role: 'assistant',
        content: `Error: ${response.data.error}`,
        created_at: new Date().toISOString(),
      });
    }
  } catch (err) {
    chatMessages.value.push({
      id: `followup-error-${Date.now()}`,
      role: 'assistant',
      content: `Error replacing follow-ups: ${err.response?.data?.error || 'An error occurred while replacing the follow-ups'}`,
      created_at: new Date().toISOString(),
    });
  } finally {
    isGenerating.value = false;
    nextTick(() => scrollToBottom());
  }
};

const keepExistingFollowups = async (messageId) => {
  const message = chatMessages.value.find(m => m.id === messageId);
  if (!message?.followUpData) return;

  // Cancel the new follow-up and keep existing ones
  try {
    await AiChatAPI.cancelFollowup(props.conversationId, message.followUpData.newFollowup.followUpId);
  } catch (err) {
    console.log('Could not cancel new follow-up:', err);
  }

  // Add message explaining the decision
  chatMessages.value.push({
    id: `followup-cancelled-${Date.now()}`,
    role: 'assistant',
    content: `✅ Understood! I've kept your existing follow-up${message.followUpData.existingFollowups.length > 1 ? 's' : ''} and cancelled the new one.`,
    created_at: new Date().toISOString(),
  });

  isInFollowUpMode.value = false;
  currentFollowUp.value = null;
  nextTick(() => scrollToBottom());
};

const changeExistingFollowup = async (messageId) => {
  const message = chatMessages.value.find(m => m.id === messageId);
  if (!message?.followUpData) return;

  // Start the follow-up editing flow with the existing follow-up
  const existingFollowup = message.followUpData.existingFollowup;
  
  chatMessages.value.push({
    id: `followup-edit-start-${Date.now()}`,
    role: 'assistant',
    content: `Let's update your follow-up message. Here's the current message:\n\n"${existingFollowup.message_content}"\n\nWhat would you like to change about it?`,
    created_at: new Date().toISOString(),
    followUpData: {
      type: 'draft_editing',
      currentMessage: existingFollowup.message_content,
      currentTime: existingFollowup.scheduled_at,
      existingFollowupId: existingFollowup.id
    }
  });

  nextTick(() => scrollToBottom());
};

const keepExistingFollowup = async (messageId) => {
  const message = chatMessages.value.find(m => m.id === messageId);
  if (!message?.followUpData) return;

  // Keep the existing follow-up and exit follow-up mode
  chatMessages.value.push({
    id: `followup-kept-${Date.now()}`,
    role: 'assistant',
    content: `✅ Perfect! I'll keep your current follow-up as is.`,
    created_at: new Date().toISOString(),
  });

  isInFollowUpMode.value = false;
  currentFollowUp.value = null;
  nextTick(() => scrollToBottom());
};

const cancelExistingFollowup = async (messageId) => {
  const message = chatMessages.value.find(m => m.id === messageId);
  if (!message?.followUpData) return;

  const existingFollowup = message.followUpData.existingFollowup;
  
  isGenerating.value = true;
  startLoadingAnimation();

  try {
    // Cancel the existing follow-up
    await AiChatAPI.cancelFollowup(props.conversationId, existingFollowup.id);
    
    // Add confirmation message
    chatMessages.value.push({
      id: `followup-cancelled-${Date.now()}`,
      role: 'assistant',
      content: `✅ I've cancelled your follow-up. It has been removed from the schedule.`,
      created_at: new Date().toISOString(),
    });

    isInFollowUpMode.value = false;
    currentFollowUp.value = null;
  } catch (err) {
    chatMessages.value.push({
      id: `followup-error-${Date.now()}`,
      role: 'assistant',
      content: `Error cancelling follow-up: ${err.response?.data?.error || 'An error occurred while cancelling the follow-up'}`,
      created_at: new Date().toISOString(),
    });
  } finally {
    isGenerating.value = false;
    nextTick(() => scrollToBottom());
  }
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
    let response;
    
    if (isInFollowUpMode.value) {
      // In follow-up mode, route to follow-up endpoint
      response = await AiChatAPI.sendFollowUpMessage(props.conversationId, message);
    } else {
      // Normal AI chat mode
      response = await AiChatAPI.sendMessage(props.conversationId, message);
    }
    
    if (response.data.success) {
      // Remove the temporary user message and add the real ones
      chatMessages.value.pop();
      chatMessages.value.push(response.data.user_message);
      chatMessages.value.push({
        ...response.data.ai_message,
        followUpData: response.data.ai_message.followUpData || null
      });
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
  
  const draftReplyMatch = response.match(/\[DRAFT REPLY\]\s*([\s\S]*?)(?=\n###|\[|$)/i);
  if (draftReplyMatch && draftReplyMatch[1]) {
    return draftReplyMatch[1]?.trim() || '';
  }
  
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
      <div class="flex gap-2">
        <button
          @click="startFollowUpFlow"
          :class="[
            'px-3 py-1 text-xs rounded flex items-center gap-1',
            isInFollowUpMode 
              ? 'bg-red-500 text-white hover:bg-red-600' 
              : 'bg-n-brand text-white hover:brightness-110'
          ]"
        >
          <Icon :icon="isInFollowUpMode ? 'i-lucide-x' : 'i-lucide-clock'" class="w-3 h-3" />
          {{ isInFollowUpMode ? 'Cancel' : 'Schedule Follow-Up' }}
        </button>
        <button
          v-if="hasChatMessages"
          @click="clearHistory"
          class="p-1 text-n-slate-10 hover:text-n-slate-12 hover:bg-n-slate-4 rounded"
          :title="$t('CONVERSATION.SIDEBAR.CLEAR_CHAT')"
        >
          <Icon icon="i-lucide-trash-2" class="w-4 h-4" />
        </button>
      </div>
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
            
            <!-- Follow-up Action Buttons -->
            <div v-if="message.followUpData" class="flex gap-2 mt-2 border-t border-n-weak pt-2">
              <!-- Draft Confirmation -->
              <template v-if="message.followUpData.type === 'draft_confirmation'">
                <button
                  @click="confirmDraftMessage(message.id)"
                  class="flex items-center gap-1 px-2 py-1 text-xs bg-n-brand text-white hover:brightness-110 rounded"
                >
                  <Icon icon="i-lucide-check" class="w-3 h-3" />
                  Confirm Message
                </button>
                <button
                  @click="editDraftMessage(message.id, 'Make it more polite')"
                  class="flex items-center gap-1 px-2 py-1 text-xs bg-n-slate-9/10 hover:bg-n-slate-9/20 rounded"
                >
                  <Icon icon="i-lucide-edit" class="w-3 h-3" />
                  More Polite
                </button>
                <button
                  @click="editDraftMessage(message.id, 'Make it shorter')"
                  class="flex items-center gap-1 px-2 py-1 text-xs bg-n-slate-9/10 hover:bg-n-slate-9/20 rounded"
                >
                  <Icon icon="i-lucide-edit" class="w-3 h-3" />
                  Shorter
                </button>
              </template>
              
              <!-- Draft Editing -->
              <template v-else-if="message.followUpData.type === 'draft_editing'">
                <button
                  @click="proceedToTimeSelection(message.id)"
                  class="flex items-center gap-1 px-2 py-1 text-xs bg-n-brand text-white hover:brightness-110 rounded"
                >
                  <Icon icon="i-lucide-clock" class="w-3 h-3" />
                  Set Time
                </button>
              </template>
              
              <!-- Time Confirmation -->
              <template v-else-if="message.followUpData.type === 'time_confirmation'">
                <button
                  @click="confirmTimeSelection(message.id)"
                  class="flex items-center gap-1 px-2 py-1 text-xs bg-n-brand text-white hover:brightness-110 rounded"
                >
                  <Icon icon="i-lucide-check" class="w-3 h-3" />
                  Confirm Time
                </button>
                <button
                  @click="editDraftMessage(message.id, 'Schedule for 1 hour later')"
                  class="flex items-center gap-1 px-2 py-1 text-xs bg-n-slate-9/10 hover:bg-n-slate-9/20 rounded"
                >
                  <Icon icon="i-lucide-clock" class="w-3 h-3" />
                  1 Hour Later
                </button>
                <button
                  @click="editDraftMessage(message.id, 'Schedule for 24 hours later')"
                  class="flex items-center gap-1 px-2 py-1 text-xs bg-n-slate-9/10 hover:bg-n-slate-9/20 rounded"
                >
                  <Icon icon="i-lucide-clock" class="w-3 h-3" />
                  24 Hours Later
                </button>
              </template>
              
              <!-- Time Editing -->
              <template v-else-if="message.followUpData.type === 'time_editing'">
                <button
                  @click="confirmTimeSelection(message.id)"
                  class="flex items-center gap-1 px-2 py-1 text-xs bg-n-brand text-white hover:brightness-110 rounded"
                >
                  <Icon icon="i-lucide-check" class="w-3 h-3" />
                  Confirm Time
                </button>
              </template>
              
              <!-- Existing Follow-up Change -->
              <template v-else-if="message.followUpData.type === 'existing_followup_change'">
                <button
                  @click="changeExistingFollowup(message.id)"
                  class="flex items-center gap-1 px-2 py-1 text-xs bg-n-brand text-white hover:brightness-110 rounded"
                >
                  <Icon icon="i-lucide-edit" class="w-3 h-3" />
                  Yes, Change It
                </button>
                <button
                  @click="keepExistingFollowup(message.id)"
                  class="flex items-center gap-1 px-2 py-1 text-xs bg-n-slate-9/10 hover:bg-n-slate-9/20 rounded"
                >
                  <Icon icon="i-lucide-x" class="w-3 h-3" />
                  Keep Current
                </button>
                <button
                  @click="cancelExistingFollowup(message.id)"
                  class="flex items-center gap-1 px-2 py-1 text-xs bg-red-500 text-white hover:bg-red-600 rounded"
                >
                  <Icon icon="i-lucide-trash-2" class="w-3 h-3" />
                  Cancel Follow-up
                </button>
              </template>
              
              <!-- Existing Follow-ups Confirmation -->
              <template v-else-if="message.followUpData.type === 'existing_followups_confirmation'">
                <button
                  @click="replaceExistingFollowups(message.id)"
                  class="flex items-center gap-1 px-2 py-1 text-xs bg-n-brand text-white hover:brightness-110 rounded"
                >
                  <Icon icon="i-lucide-refresh-cw" class="w-3 h-3" />
                  Replace Existing
                </button>
                <button
                  @click="keepExistingFollowups(message.id)"
                  class="flex items-center gap-1 px-2 py-1 text-xs bg-n-slate-9/10 hover:bg-n-slate-9/20 rounded"
                >
                  <Icon icon="i-lucide-x" class="w-3 h-3" />
                  Keep Existing
                </button>
              </template>
            </div>
            
            <!-- Regular Action Buttons -->
            <div v-else class="flex gap-2 mt-2 border-t border-n-weak pt-2">
              <button
                @click="copyToClipboard(message.content.includes('[DRAFT REPLY]') || message.content.includes('Draft Response') ? extractDraftResponse(message.content) : message.content)"
                class="flex items-center gap-1 px-2 py-1 text-xs bg-n-slate-9/10 hover:bg-n-slate-9/20 rounded"
              >
                <Icon icon="i-lucide-copy" class="w-3 h-3" />
                Copy
              </button>
              <button
                v-if="message.content.includes('[DRAFT REPLY]') || message.content.includes('Draft Response')"
                @click="insertIntoEditor(extractDraftResponse(message.content))"
                class="flex items-center gap-1 px-2 py-1 text-xs bg-n-slate-9/10 hover:bg-n-slate-9/20 rounded"
              >
                <Icon icon="i-lucide-message-square" class="w-3 h-3" />
                Insert
              </button>
              <button
                v-if="message.content.includes('[DRAFT REPLY]') || message.content.includes('Draft Response')"
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
      <div class="mb-3 flex gap-2">
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
          class="flex-1 px-3 py-2 h-12 !mb-0 border border-gray-300 rounded-lg text-sm focus:outline-none focus:ring-2 focus:ring-blue-500 focus:border-transparent"
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