/* global axios */
import ApiClient from './ApiClient';

class AiChatAPI extends ApiClient {
    constructor() {
        super('conversations', { accountScoped: true });
    }

    // Send a message to AI chat
    sendMessage(conversationId, message) {
        return axios.post(`${this.url}/${conversationId}/ai_chat_send_message`, {
            message,
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
}

export default new AiChatAPI();
