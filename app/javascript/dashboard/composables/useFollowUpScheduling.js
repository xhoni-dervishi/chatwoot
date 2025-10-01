import { ref, computed } from 'vue';
import AiChatAPI from '../api/aiChat';

export function useFollowUpScheduling(conversationId) {
    const isAnalyzing = ref(false);
    const isCreating = ref(false);
    const isUpdating = ref(false);
    const error = ref('');

    // Follow-up state
    const followupAnalysis = ref(null);
    const currentFollowup = ref(null);
    const followupStep = ref('idle'); // 'idle', 'analyzing', 'draft', 'time', 'confirming', 'scheduled'

    // Computed properties
    const shouldShowFollowup = computed(() => followupAnalysis.value?.should_followup);
    const canScheduleFollowup = computed(() => followupStep.value === 'confirming');

    // Analyze conversation for follow-up
    const analyzeConversation = async () => {
        if (isAnalyzing.value) return;

        isAnalyzing.value = true;
        error.value = '';
        followupStep.value = 'analyzing';

        try {
            const response = await AiChatAPI.scheduleFollowup(conversationId);

            if (response.data.success) {
                followupAnalysis.value = response.data;

                if (response.data.should_followup) {
                    followupStep.value = 'draft';
                } else {
                    followupStep.value = 'idle';
                }
            } else {
                error.value = response.data.error || 'Failed to analyze conversation';
                followupStep.value = 'idle';
            }
        } catch (err) {
            console.error('Follow-up analysis error:', err);
            error.value = err.response?.data?.error || 'An error occurred while analyzing the conversation';
            followupStep.value = 'idle';
        } finally {
            isAnalyzing.value = false;
        }
    };

    // Create scheduled follow-up
    const createFollowup = async (messageContent, scheduledAt, metadata = {}) => {
        if (isCreating.value) return;

        isCreating.value = true;
        error.value = '';

        try {
            const response = await AiChatAPI.createFollowup(conversationId, messageContent, scheduledAt, metadata);

            if (response.data.success) {
                currentFollowup.value = response.data.scheduled_followup;
                followupStep.value = 'scheduled';
                return response.data.scheduled_followup;
            } else {
                error.value = response.data.error || 'Failed to create scheduled follow-up';
                return null;
            }
        } catch (err) {
            console.error('Create follow-up error:', err);
            error.value = err.response?.data?.error || 'An error occurred while creating the scheduled follow-up';
            return null;
        } finally {
            isCreating.value = false;
        }
    };

    // Update follow-up draft
    const updateDraft = async (followupId, newContent = null, userRequest = null) => {
        if (isUpdating.value) return;

        isUpdating.value = true;
        error.value = '';

        try {
            const response = await AiChatAPI.updateFollowupDraft(conversationId, followupId, newContent, userRequest);

            if (response.data.success) {
                currentFollowup.value = response.data.scheduled_followup;
                return response.data.scheduled_followup;
            } else {
                error.value = response.data.error || 'Failed to update draft';
                return null;
            }
        } catch (err) {
            console.error('Update draft error:', err);
            error.value = err.response?.data?.error || 'An error occurred while updating the draft';
            return null;
        } finally {
            isUpdating.value = false;
        }
    };

    // Update draft with AI (before follow-up is created)
    const updateDraftWithAI = async (currentDraft, userRequest) => {
        if (isUpdating.value) return;

        isUpdating.value = true;
        error.value = '';

        try {
            // Use the AI chat API to generate an updated draft
            const response = await AiChatAPI.sendFollowUpMessage(conversationId, `Please update this follow-up message: "${currentDraft}" based on this request: "${userRequest}". Return only the updated message.`);

            if (response.data.success) {
                return response.data.ai_message.content;
            } else {
                error.value = response.data.error || 'Failed to update draft with AI';
                return null;
            }
        } catch (err) {
            console.error('Update draft with AI error:', err);
            error.value = err.response?.data?.error || 'An error occurred while updating the draft with AI';
            return null;
        } finally {
            isUpdating.value = false;
        }
    };

    // Update follow-up time
    const updateTime = async (followupId, scheduledAt) => {
        if (isUpdating.value) return;

        isUpdating.value = true;
        error.value = '';

        try {
            const response = await AiChatAPI.updateFollowupTime(conversationId, followupId, scheduledAt);

            if (response.data.success) {
                currentFollowup.value = response.data.scheduled_followup;
                return response.data.scheduled_followup;
            } else {
                error.value = response.data.error || 'Failed to update scheduled time';
                return null;
            }
        } catch (err) {
            console.error('Update time error:', err);
            error.value = err.response?.data?.error || 'An error occurred while updating the scheduled time';
            return null;
        } finally {
            isUpdating.value = false;
        }
    };

    // Flow control methods
    const startFollowupFlow = () => {
        followupStep.value = 'analyzing';
        analyzeConversation();
    };

    const proceedToTimeSelection = () => {
        followupStep.value = 'time';
    };

    const proceedToConfirmation = () => {
        followupStep.value = 'confirming';
    };

    const resetFlow = () => {
        followupStep.value = 'idle';
        followupAnalysis.value = null;
        currentFollowup.value = null;
        error.value = '';
    };

    // Format time for display
    const formatScheduledTime = (dateString) => {
        const date = new Date(dateString);
        return date.toLocaleString('en-US', {
            weekday: 'short',
            month: 'short',
            day: 'numeric',
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        });
    };

    // Calculate suggested time options
    const getTimeOptions = (baseTime) => {
        const base = new Date(baseTime);
        return [
            { label: '1 hour', value: new Date(base.getTime() + 1 * 60 * 60 * 1000) },
            { label: '6 hours', value: new Date(base.getTime() + 6 * 60 * 60 * 1000) },
            { label: '12 hours', value: new Date(base.getTime() + 12 * 60 * 60 * 1000) },
            { label: '24 hours', value: new Date(base.getTime() + 24 * 60 * 60 * 1000) },
            { label: '48 hours', value: new Date(base.getTime() + 48 * 60 * 60 * 1000) },
            { label: '1 week', value: new Date(base.getTime() + 7 * 24 * 60 * 60 * 1000) },
        ];
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

        // Computed
        shouldShowFollowup,
        canScheduleFollowup,

        // Methods
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
    };
}
