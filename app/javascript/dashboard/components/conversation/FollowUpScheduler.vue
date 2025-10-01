<script>
import { computed, ref, watch } from 'vue';
import { useFollowUpScheduling } from '../../composables/useFollowUpScheduling';
import Icon from 'dashboard/components-next/icon/Icon.vue';

export default {
  name: 'FollowUpScheduler',
  components: {
    Icon,
  },
  props: {
    conversationId: {
      type: [String, Number],
      required: true,
    },
  },
  emits: ['close', 'scheduled'],
  setup(props, { emit }) {
    const {
      isAnalyzing,
      isCreating,
      isUpdating,
      error,
      followupAnalysis,
      currentFollowup,
      followupStep,
      shouldShowFollowup,
      canScheduleFollowup,
      analyzeConversation,
      createFollowup,
      updateDraft,
      updateDraftWithAI,
      updateTime,
      startFollowupFlow,
      proceedToTimeSelection,
      proceedToConfirmation,
      resetFlow,
      formatScheduledTime,
      getTimeOptions,
    } = useFollowUpScheduling(props.conversationId);

    // Local state for the flow
    const selectedTime = ref(null);
    const customTimeInput = ref('');
    const isEditingDraft = ref(false);
    const draftEditRequest = ref('');
    
    // Use composable's draft message
    const draftMessage = computed(() => followupAnalysis.value?.draft_message || '');

    // Watch for analysis completion to set initial time
    watch(() => followupAnalysis.value, (newAnalysis) => {
      if (newAnalysis?.should_followup && newAnalysis.suggested_time) {
        selectedTime.value = new Date(newAnalysis.suggested_time);
      }
    });

    // Computed properties
    const timeOptions = computed(() => {
      if (selectedTime.value) {
        return getTimeOptions(selectedTime.value);
      }
      return getTimeOptions(new Date(Date.now() + 24 * 60 * 60 * 1000)); // Default to 24h from now
    });

    const formattedSelectedTime = computed(() => {
      return selectedTime.value ? formatScheduledTime(selectedTime.value.toISOString()) : '';
    });

    // Methods
    const handleStartFollowup = () => {
      startFollowupFlow();
    };

    const handleDraftEdit = async () => {
      if (!draftEditRequest.value.trim()) return;
      
      try {
        const updatedMessage = await updateDraftWithAI(draftMessage.value, draftEditRequest.value);
        
        if (updatedMessage) {
          // Update the composable's analysis with the new draft
          followupAnalysis.value.draft_message = updatedMessage;
          draftEditRequest.value = '';
          isEditingDraft.value = false;
        }
      } catch (error) {
        console.error('Error updating draft:', error);
        // Fallback: just close the edit mode
        draftEditRequest.value = '';
        isEditingDraft.value = false;
      }
    };

    const handleTimeChange = (timeOption) => {
      selectedTime.value = timeOption.value;
    };

    const handleCustomTimeChange = () => {
      if (customTimeInput.value) {
        const customTime = new Date(customTimeInput.value);
        if (!isNaN(customTime.getTime())) {
          selectedTime.value = customTime;
        }
      }
    };

    const handleConfirmSchedule = async () => {
      if (!draftMessage.value.trim() || !selectedTime.value) return;
      
      const scheduled = await createFollowup(
        draftMessage.value,
        selectedTime.value.toISOString(),
        { 
          created_via: 'ai_chat',
          original_analysis: followupAnalysis.value 
        }
      );
      
      if (scheduled) {
        emit('scheduled', scheduled);
        resetFlow();
      }
    };

    const handleClose = () => {
      resetFlow();
      emit('close');
    };

    return {
      // State
      isAnalyzing,
      isCreating,
      isUpdating,
      error,
      followupAnalysis,
      currentFollowup,
      followupStep,
      draftMessage,
      selectedTime,
      customTimeInput,
      isEditingDraft,
      draftEditRequest,
      
      // Computed
      shouldShowFollowup,
      canScheduleFollowup,
      timeOptions,
      formattedSelectedTime,
      
      // Methods
      handleStartFollowup,
      handleDraftEdit,
      handleTimeChange,
      handleCustomTimeChange,
      handleConfirmSchedule,
      handleClose,
    };
  },
};
</script>

<template>
  <div class="follow-up-scheduler">
    <!-- Analysis Step -->
    <div v-if="followupStep === 'analyzing'" class="flex items-center gap-3 p-4">
      <div class="w-8 h-8 bg-n-brand rounded-full flex items-center justify-center flex-shrink-0">
        <Icon icon="i-lucide-loader-pinwheel" class="w-4 h-4 text-white animate-spin" />
      </div>
      <div class="flex-1">
        <p class="text-sm text-n-slate-12">Analyzing conversation for follow-up opportunities...</p>
      </div>
    </div>

    <!-- No Follow-up Needed -->
    <div v-else-if="followupStep === 'idle' && followupAnalysis && !shouldShowFollowup" class="flex items-center gap-3 p-4">
      <div class="w-8 h-8 bg-n-slate-4 rounded-full flex items-center justify-center flex-shrink-0">
        <Icon icon="i-lucide-check-circle" class="w-4 h-4 text-n-slate-10" />
      </div>
      <div class="flex-1">
        <p class="text-sm text-n-slate-12">{{ followupAnalysis.reason }}</p>
      </div>
    </div>

    <!-- Draft Step -->
    <div v-else-if="followupStep === 'draft'" class="space-y-4 p-4">
      <div class="flex items-start gap-3">
        <div class="w-8 h-8 bg-n-brand rounded-full flex items-center justify-center flex-shrink-0">
          <Icon icon="i-lucide-sparkles" class="w-4 h-4 text-white" />
        </div>
        <div class="flex-1">
          <p class="text-sm text-n-slate-12 mb-2">{{ followupAnalysis.reasoning }}</p>
          <p class="text-sm text-n-slate-10 mb-3">Here's a draft you can use:</p>
          
          <div class="bg-n-slate-4 rounded-lg p-3 mb-3">
            <textarea
              v-model="draftMessage"
              class="w-full bg-transparent border-none resize-none text-sm text-n-slate-12 focus:outline-none"
              rows="3"
              placeholder="Draft message..."
            />
          </div>
          
          <div class="flex gap-2">
            <button
              @click="isEditingDraft = !isEditingDraft"
              class="flex items-center gap-1 px-2 py-1 text-xs bg-n-slate-9/10 hover:bg-n-slate-9/20 rounded"
            >
              <Icon icon="i-lucide-edit" class="w-3 h-3" />
              Edit with AI
            </button>
            <button
              @click="proceedToTimeSelection"
              class="flex items-center gap-1 px-2 py-1 text-xs bg-n-brand text-white hover:brightness-110 rounded"
            >
              <Icon icon="i-lucide-clock" class="w-3 h-3" />
              Set Time
            </button>
          </div>
        </div>
      </div>

      <!-- AI Edit Request -->
      <div v-if="isEditingDraft" class="flex items-start gap-3 ml-11">
        <div class="w-6 h-6 bg-n-slate-4 rounded-full flex items-center justify-center flex-shrink-0">
          <Icon icon="i-lucide-message-circle" class="w-3 h-3 text-n-slate-10" />
        </div>
        <div class="flex-1">
          <input
            v-model="draftEditRequest"
            @keydown.enter="handleDraftEdit"
            placeholder="How would you like me to modify the message? (e.g., 'Make it more polite', 'Add an emoji')"
            class="w-full px-3 py-2 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
          />
          <div class="flex gap-2 mt-2">
            <button
              @click="handleDraftEdit"
              :disabled="!draftEditRequest.trim() || isUpdating"
              class="px-2 py-1 text-xs bg-n-brand text-white hover:brightness-110 disabled:opacity-50 rounded"
            >
              {{ isUpdating ? 'Updating...' : 'Update' }}
            </button>
            <button
              @click="isEditingDraft = false; draftEditRequest = ''"
              class="px-2 py-1 text-xs bg-n-slate-9/10 hover:bg-n-slate-9/20 rounded"
            >
              Cancel
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Time Selection Step -->
    <div v-else-if="followupStep === 'time'" class="space-y-4 p-4">
      <div class="flex items-start gap-3">
        <div class="w-8 h-8 bg-n-brand rounded-full flex items-center justify-center flex-shrink-0">
          <Icon icon="i-lucide-clock" class="w-4 h-4 text-white" />
        </div>
        <div class="flex-1">
          <p class="text-sm text-n-slate-12 mb-3">When should I send this?</p>
          
          <div class="space-y-2 mb-4">
            <div v-for="option in timeOptions" :key="option.label" class="flex items-center gap-2">
              <input
                :id="`time-${option.label}`"
                type="radio"
                :value="option.value"
                v-model="selectedTime"
                class="text-n-brand focus:ring-n-brand"
              />
              <label :for="`time-${option.label}`" class="text-sm text-n-slate-12">
                {{ option.label }} ({{ formatScheduledTime(option.value.toISOString()) }})
              </label>
            </div>
          </div>
          
          <div class="mb-4">
            <label class="block text-xs text-n-slate-10 mb-1">Or specify custom time:</label>
            <input
              v-model="customTimeInput"
              @change="handleCustomTimeChange"
              type="datetime-local"
              class="w-full px-3 py-2 text-sm border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-blue-500"
            />
          </div>
          
          <div class="flex gap-2">
            <button
              @click="followupStep = 'draft'"
              class="px-2 py-1 text-xs bg-n-slate-9/10 hover:bg-n-slate-9/20 rounded"
            >
              Back to Draft
            </button>
            <button
              @click="proceedToConfirmation"
              :disabled="!selectedTime"
              class="px-2 py-1 text-xs bg-n-brand text-white hover:brightness-110 disabled:opacity-50 rounded"
            >
              Confirm Time
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Confirmation Step -->
    <div v-else-if="followupStep === 'confirming'" class="space-y-4 p-4">
      <div class="flex items-start gap-3">
        <div class="w-8 h-8 bg-n-brand rounded-full flex items-center justify-center flex-shrink-0">
          <Icon icon="i-lucide-check-circle" class="w-4 h-4 text-white" />
        </div>
        <div class="flex-1">
          <p class="text-sm text-n-slate-12 mb-3">Ready to schedule your follow-up:</p>
          
          <div class="bg-n-slate-4 rounded-lg p-3 mb-3">
            <p class="text-sm text-n-slate-12 mb-2">{{ draftMessage }}</p>
            <p class="text-xs text-n-slate-10">Scheduled for: {{ formattedSelectedTime }}</p>
          </div>
          
          <div class="flex gap-2">
            <button
              @click="followupStep = 'time'"
              class="px-2 py-1 text-xs bg-n-slate-9/10 hover:bg-n-slate-9/20 rounded"
            >
              Change Time
            </button>
            <button
              @click="handleConfirmSchedule"
              :disabled="isCreating"
              class="px-2 py-1 text-xs bg-green-600 text-white hover:brightness-110 disabled:opacity-50 rounded"
            >
              {{ isCreating ? 'Scheduling...' : 'Schedule Follow-up' }}
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Scheduled Success -->
    <div v-else-if="followupStep === 'scheduled'" class="flex items-center gap-3 p-4">
      <div class="w-8 h-8 bg-green-500 rounded-full flex items-center justify-center flex-shrink-0">
        <Icon icon="i-lucide-check" class="w-4 h-4 text-white" />
      </div>
      <div class="flex-1">
        <p class="text-sm text-n-slate-12">✅ Perfect! Your follow-up has been scheduled successfully.</p>
        <p class="text-xs text-n-slate-10">I'll send the message at the specified time.</p>
      </div>
    </div>

    <!-- Error State -->
    <div v-if="error" class="flex items-start gap-3 p-4">
      <div class="w-8 h-8 bg-red-500 rounded-full flex items-center justify-center flex-shrink-0">
        <Icon icon="i-lucide-alert-triangle" class="w-4 h-4 text-white" />
      </div>
      <div class="flex-1">
        <p class="text-sm text-red-800">{{ error }}</p>
      </div>
    </div>

    <!-- Start Button -->
    <div v-if="followupStep === 'idle' && !followupAnalysis" class="p-4">
      <button
        @click="handleStartFollowup"
        :disabled="isAnalyzing"
        class="w-full flex items-center justify-center gap-2 px-4 py-3 bg-n-brand text-white rounded-lg hover:brightness-110 disabled:opacity-50 disabled:cursor-not-allowed"
      >
        <Icon icon="i-lucide-clock" class="w-4 h-4" />
        {{ isAnalyzing ? 'Analyzing...' : 'Schedule Follow-Up' }}
      </button>
    </div>
  </div>
</template>

<style scoped>
.follow-up-scheduler {
  border-top: 1px solid var(--color-n-weak);
}
</style>
