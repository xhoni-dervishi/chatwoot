/**
 * Utility functions for timezone handling in the dashboard
 */

/**
 * Get the user's browser timezone
 * @returns {string} The user's timezone (e.g., 'America/New_York')
 */
export const getUserTimezone = () => {
    return Intl.DateTimeFormat().resolvedOptions().timeZone;
};

/**
 * Format a date string to display in the user's timezone
 * @param {string|Date} dateString - ISO date string or Date object
 * @param {Object} options - Intl.DateTimeFormat options
 * @returns {string} Formatted date string in user's timezone
 */
export const formatDateInUserTimezone = (dateString, options = {}) => {
    const date = new Date(dateString);
    const userTimezone = getUserTimezone();

    const defaultOptions = {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        hour12: true,
        timeZone: userTimezone,
        ...options
    };

    return date.toLocaleString('en-US', defaultOptions);
};

/**
 * Format a date string for display in chat messages
 * @param {string|Date} dateString - ISO date string or Date object
 * @returns {string} Formatted date string for chat display
 */
export const formatDateForChat = (dateString) => {
    return formatDateInUserTimezone(dateString, {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        hour12: true
    });
};

/**
 * Format a date string for display in UI components
 * @param {string|Date} dateString - ISO date string or Date object
 * @returns {string} Formatted date string for UI display
 */
export const formatDateForUI = (dateString) => {
    return formatDateInUserTimezone(dateString, {
        weekday: 'short',
        month: 'short',
        day: 'numeric',
        hour: 'numeric',
        minute: '2-digit',
        hour12: true
    });
};

/**
 * Convert a date to the user's timezone and return as Date object
 * @param {string|Date} dateString - ISO date string or Date object
 * @returns {Date} Date object in user's timezone
 */
export const convertToUserTimezone = (dateString) => {
    const date = new Date(dateString);
    const userTimezone = getUserTimezone();

    // Create a new date with the same UTC time but displayed in user timezone
    return new Date(date.toLocaleString('en-US', { timeZone: userTimezone }));
};

/**
 * Get timezone offset information for debugging
 * @returns {Object} Timezone information
 */
export const getTimezoneInfo = () => {
    const userTimezone = getUserTimezone();
    const now = new Date();

    return {
        userTimezone,
        utcOffset: now.getTimezoneOffset(),
        localTime: now.toLocaleString(),
        utcTime: now.toUTCString()
    };
};
