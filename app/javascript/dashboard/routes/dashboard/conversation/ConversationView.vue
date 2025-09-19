<script>
import { mapGetters } from 'vuex';
import { useUISettings } from 'dashboard/composables/useUISettings';
import { useAccount } from 'dashboard/composables/useAccount';
import ChatList from '../../../components/ChatList.vue';
import ConversationBox from '../../../components/widgets/conversation/ConversationBox.vue';
import wootConstants from 'dashboard/constants/globals';
import { BUS_EVENTS } from 'shared/constants/busEvents';
import CmdBarConversationSnooze from 'dashboard/routes/dashboard/commands/CmdBarConversationSnooze.vue';
import { emitter } from 'shared/helpers/mitt';
import SidepanelSwitch from 'dashboard/components-next/Conversation/SidepanelSwitch.vue';
import ConversationSidebar from 'dashboard/components/widgets/conversation/ConversationSidebar.vue';
import AIResponsePanel from 'dashboard/routes/dashboard/conversation/AIResponsePanel.vue';

export default {
  components: {
    ChatList,
    ConversationBox,
    CmdBarConversationSnooze,
    SidepanelSwitch,
    ConversationSidebar,
    AIResponsePanel,
  },
  beforeRouteLeave(to, from, next) {
    // Clear selected state if navigating away from a conversation to a route without a conversationId to prevent stale data issues
    // and resolves timing issues during navigation with conversation view and other screens
    if (this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
    next(); // Continue with navigation
  },
  props: {
    inboxId: {
      type: [String, Number],
      default: 0,
    },
    conversationId: {
      type: [String, Number],
      default: 0,
    },
    label: {
      type: String,
      default: '',
    },
    teamId: {
      type: String,
      default: '',
    },
    conversationType: {
      type: String,
      default: '',
    },
    foldersId: {
      type: [String, Number],
      default: 0,
    },
  },
  setup() {
    const { uiSettings, updateUISettings } = useUISettings();
    const { accountId } = useAccount();

    return {
      uiSettings,
      updateUISettings,
      accountId,
    };
  },
  data() {
    return {
      showSearchModal: false,
      // Resize functionality
      dividerPosition: parseFloat(localStorage.getItem('conversation-divider-position')) || 25, // 25% from right
      isDragging: false,
    };
  },
  computed: {
    ...mapGetters({
      chatList: 'getAllConversations',
      currentChat: 'getSelectedChat',
    }),
    showConversationList() {
      return this.isOnExpandedLayout ? !this.conversationId : true;
    },
    showMessageView() {
      return this.conversationId ? true : !this.isOnExpandedLayout;
    },
    isOnExpandedLayout() {
      const {
        LAYOUT_TYPES: { CONDENSED },
      } = wootConstants;
      const { conversation_display_type: conversationDisplayType = CONDENSED } =
        this.uiSettings;
      return conversationDisplayType !== CONDENSED;
    },

    shouldShowSidebar() {
      if (!this.currentChat.id) {
        return false;
      }

      const { is_contact_sidebar_open: isContactSidebarOpen } = this.uiSettings;
      return isContactSidebarOpen;
    },
    shouldShowAIResponsePanel() {
      if (!this.currentChat.id) {
        return false;
      }
      const { is_ai_response_panel_open: isAIResponsePanelOpen } = this.uiSettings;
      return isAIResponsePanelOpen;
    },
    isRTL() {
      return document.dir === 'rtl' || document.documentElement.dir === 'rtl';
    },
    isDraggingClass() {
      return this.isDragging ? 'resizing' : '';
    },
    isMobile() {
      return window.innerWidth < 768; // md breakpoint
    },
    shouldShowResizeDivider() {
      return !this.isMobile && (this.shouldShowSidebar || this.shouldShowAIResponsePanel);
    },
    sidebarWidth() {
      return this.isMobile ? '100%' : `${this.dividerPosition}%`;
    },
    mainContentWidth() {
      return this.isMobile ? '100%' : `${100 - this.dividerPosition}%`;
    },
  },
  watch: {
    conversationId() {
      this.fetchConversationIfUnavailable();
    },
  },

  created() {
    // Clear selected state early if no conversation is selected
    // This prevents child components from accessing stale data
    // and resolves timing issues during navigation
    // with conversation view and other screens
    if (!this.conversationId) {
      this.$store.dispatch('clearSelectedState');
    }
  },

  mounted() {
    this.$store.dispatch('agents/get');
    this.$store.dispatch('portals/index');
    this.initialize();
    this.$watch('$store.state.route', () => this.initialize());
    this.$watch('chatList.length', () => {
      this.setActiveChat();
    });
  },
  beforeDestroy() {
    // Cleanup resize event listeners
    document.removeEventListener('mousemove', this.handleDragging);
  },

  methods: {
    onConversationLoad() {
      this.fetchConversationIfUnavailable();
    },
    initialize() {
      this.$store.dispatch('setActiveInbox', this.inboxId);
      this.setActiveChat();
    },
    toggleConversationLayout() {
      const { LAYOUT_TYPES } = wootConstants;
      const {
        conversation_display_type:
          conversationDisplayType = LAYOUT_TYPES.CONDENSED,
      } = this.uiSettings;
      const newViewType =
        conversationDisplayType === LAYOUT_TYPES.CONDENSED
          ? LAYOUT_TYPES.EXPANDED
          : LAYOUT_TYPES.CONDENSED;
      this.updateUISettings({
        conversation_display_type: newViewType,
        previously_used_conversation_display_type: newViewType,
      });
    },
    fetchConversationIfUnavailable() {
      if (!this.conversationId) {
        return;
      }
      const chat = this.findConversation();
      if (!chat) {
        this.$store.dispatch('getConversation', this.conversationId);
      }
    },
    findConversation() {
      const conversationId = parseInt(this.conversationId, 10);
      const [chat] = this.chatList.filter(c => c.id === conversationId);
      return chat;
    },
    setActiveChat() {
      if (this.conversationId) {
        const selectedConversation = this.findConversation();
        // If conversation doesn't exist or selected conversation is same as the active
        // conversation, don't set active conversation.
        if (
          !selectedConversation ||
          selectedConversation.id === this.currentChat.id
        ) {
          return;
        }
        const { messageId } = this.$route.query;
        this.$store
          .dispatch('setActiveChat', {
            data: selectedConversation,
            after: messageId,
          })
          .then(() => {
            emitter.emit(BUS_EVENTS.SCROLL_TO_MESSAGE, { messageId });
          });
      } else {
        this.$store.dispatch('clearSelectedState');
      }
    },
    onSearch() {
      this.showSearchModal = true;
    },
    closeSearch() {
      this.showSearchModal = false;
    },
    closeMobileSidebar() {
      if (this.isMobile) {
        // Close both sidebars on mobile
        this.updateUISettings({
          is_contact_sidebar_open: false,
          is_ai_response_panel_open: false,
        });
      }
    },
    // Resize handlers based on the example (desktop only)
    handleDragging(e) {
      if (!this.isDragging || this.isMobile) return;
      
      let percentage;
      
      if (this.isRTL) {
        // For RTL, calculate from left edge
        percentage = (e.pageX / window.innerWidth) * 100;
      } else {
        // For LTR, calculate from right edge (inverted)
        percentage = ((window.innerWidth - e.pageX) / window.innerWidth) * 100;
      }
      
      // Constrain between 15% and 50% (reasonable sidebar width range)
      if (percentage >= 15 && percentage <= 50) {
        this.dividerPosition = parseFloat(percentage.toFixed(2));
      }
    },
    startDragging() {
      if (this.isMobile) return;
      this.isDragging = true;
      document.addEventListener('mousemove', this.handleDragging);
    },
    endDragging() {
      if (this.isMobile) return;
      this.isDragging = false;
      document.removeEventListener('mousemove', this.handleDragging);
      // Save position to localStorage
      localStorage.setItem('conversation-divider-position', this.dividerPosition.toString());
    },
  },
};
</script>

<template>
  <section 
    class="flex w-full h-full min-w-0 relative" 
    :class="isDraggingClass"
    @mouseup="endDragging()"
  >
    <ChatList
      :show-conversation-list="showConversationList"
      :conversation-inbox="inboxId"
      :label="label"
      :team-id="teamId"
      :conversation-type="conversationType"
      :folders-id="foldersId"
      :is-on-expanded-layout="isOnExpandedLayout"
      @conversation-load="onConversationLoad"
    />
    
    <!-- Main Content Area -->
    <div 
      class="flex flex-1 min-w-0"
      :style="{ width: mainContentWidth }"
    >
      <ConversationBox
        v-if="showMessageView"
        :inbox-id="inboxId"
        :is-on-expanded-layout="isOnExpandedLayout"
      >
        <SidepanelSwitch v-if="currentChat.id" />
      </ConversationBox>
    </div>

    <!-- Resize Divider (Desktop only) -->
    <div
      v-if="shouldShowResizeDivider"
      class="divider"
      :style="{
        right: isRTL ? `${100 - dividerPosition}%` : `${dividerPosition}%`
      }"
      @mousedown="startDragging()"
    ></div>

    <!-- Mobile Overlay -->
    <div 
      v-if="isMobile && (shouldShowSidebar || shouldShowAIResponsePanel)"
      class="mobile-overlay show"
      @click="closeMobileSidebar"
    ></div>

    <!-- Sidebar Area -->
    <div 
      v-if="shouldShowSidebar || shouldShowAIResponsePanel"
      class="flex flex-col"
      :class="{ 
        'mobile-sidebar': isMobile,
        'show': isMobile && (shouldShowSidebar || shouldShowAIResponsePanel)
      }"
      :style="{ width: sidebarWidth }"
    >
      <ConversationSidebar v-if="shouldShowSidebar" :current-chat="currentChat" />
      <AIResponsePanel v-if="shouldShowAIResponsePanel" :conversation-id="currentChat.id" />
    </div>
    
    <CmdBarConversationSnooze />
  </section>
</template>

<style scoped>
.divider {
  height: 100vh;
  width: 6px;
  background: #fff;
  transform: translateX(-3px);
  position: absolute;
  top: 0;
  z-index: 1;
  cursor: ew-resize;
  border: 1px solid #e5e7eb;
  transition: background-color 0.2s ease;
}

.divider:hover {
  background: #3b82f6;
  border-color: #3b82f6;
}

/* RTL support for divider */
[dir="rtl"] .divider {
  transform: translateX(3px);
}

/* Prevent text selection during resize */
.resizing {
  user-select: none;
  -webkit-user-select: none;
  -moz-user-select: none;
  -ms-user-select: none;
}

.resizing * {
  user-select: none;
  -webkit-user-select: none;
  -moz-user-select: none;
  -ms-user-select: none;
}

/* Mobile sidebar styles */
.mobile-sidebar {
  position: fixed;
  top: 0;
  right: 0;
  height: 100vh;
  z-index: 50;
  background: white;
  box-shadow: -4px 0 6px -1px rgba(0, 0, 0, 0.1);
  transform: translateX(100%);
  transition: transform 0.3s ease-in-out;
}

/* Show mobile sidebar when active */
.mobile-sidebar.show {
  transform: translateX(0);
}

/* Mobile overlay */
.mobile-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.5);
  z-index: 40;
  opacity: 0;
  visibility: hidden;
  transition: opacity 0.3s ease-in-out, visibility 0.3s ease-in-out;
}

.mobile-overlay.show {
  opacity: 1;
  visibility: visible;
}
</style>
