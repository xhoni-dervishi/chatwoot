/* global axios */
import ApiClient from './ApiClient';

class AIApi extends ApiClient {
    constructor() {
        super('conversations', { accountScoped: true });
    }

    /**
     * Generate AI response for a conversation
     * @param {number} conversationId - The conversation ID
     * @param {string} customPrompt - The custom prompt
     * @returns {Promise} A promise that resolves with the AI response
     */
    generateResponse(conversationId, customPrompt) {
        return axios.post(`${this.url}/${conversationId}/ai_generate_response`, { customPrompt });
    }
}

export default new AIApi();
