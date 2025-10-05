/* global axios */
import ApiClient from './ApiClient';

class AiChatAPI extends ApiClient {
    constructor() {
        super('conversations', { accountScoped: true });
    }

    // Send a message to AI chat
    sendMessage(conversationId, message) {
        // Get user's timezone information
        const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
        const timezoneOffset = new Date().getTimezoneOffset() / -60; // Convert to hours, positive for ahead of UTC

        return axios.post(`${this.url}/${conversationId}/ai_chat_send_message`, {
            message,
            timezone: timezone,
            timezone_offset: timezoneOffset
        });
    }

    // Get AI chat history
    getHistory(conversationId) {
        return axios.get(`${this.url}/${conversationId}/ai_chat_history`);
    }

    // Clear AI chat history
    clearHistory(conversationId) {
        return axios.delete(`${this.url}/${conversationId}/ai_chat_clear_history`);
    }

    // Schedule Follow-Up endpoints
    scheduleFollowup(conversationId) {
        return axios.post(`${this.url}/${conversationId}/ai_chat_schedule_followup`);
    }

    createFollowup(conversationId, messageContent, scheduledAt, metadata = {}) {
        return axios.post(`${this.url}/${conversationId}/ai_chat_create_followup`, {
            message_content: messageContent,
            scheduled_at: scheduledAt,
            metadata,
        });
    }

    updateFollowupDraft(conversationId, followupId, newContent = null, userRequest = null) {
        return axios.put(`${this.url}/${conversationId}/ai_chat_update_followup_draft/${followupId}`, {
            new_content: newContent,
            user_request: userRequest,
        });
    }

    updateFollowupTime(conversationId, followupId, scheduledAt) {
        return axios.put(`${this.url}/${conversationId}/ai_chat_update_followup_time/${followupId}`, {
            scheduled_at: scheduledAt,
        });
    }

    getExistingFollowups(conversationId) {
        return axios.get(`${this.url}/${conversationId}/ai_chat_existing_followups`);
    }

    cancelFollowup(conversationId, followupId) {
        return axios.delete(`${this.url}/${conversationId}/ai_chat_cancel_followup/${followupId}`);
    }

    sendFollowUpMessage(conversationId, message) {
        // Get user's timezone information
        const timezone = Intl.DateTimeFormat().resolvedOptions().timeZone;
        const timezoneOffset = new Date().getTimezoneOffset() / -60; // Convert to hours, positive for ahead of UTC

        return axios.post(`${this.url}/${conversationId}/ai_chat_send_message`, {
            message,
            follow_up_mode: true,
            timezone: timezone,
            timezone_offset: timezoneOffset
        });
    }
}

export default new AiChatAPI();
