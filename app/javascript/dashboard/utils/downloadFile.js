/**
 * Downloads a file from a URL with proper file type handling
 * @name downloadFile
 * @description Downloads file from URL with proper type handling and cleanup
 * @param {Object} options Download configuration options
 * @param {string} options.url File URL to download
 * @param {string} options.type File type identifier
 * @param {string} [options.extension] Optional file extension
 * @returns {Promise<void>} Returns void when download is initiated
 */
export const downloadFile = async ({
    url,
    type,
    extension = null,
}) => {
    if (!url || !type) {
        throw new Error('Invalid download parameters');
    }

    try {
        // For S3 URLs and cross-origin requests, we need to fetch as blob
        const response = await fetch(url, {
            cache: 'no-store',
            mode: 'cors', // Enable CORS for cross-origin requests
        });

        if (!response.ok) {
            throw new Error(`Download failed: ${response.status} ${response.statusText}`);
        }

        const blobData = await response.blob();

        // Get content type from response headers
        const contentType = response.headers.get('content-type');

        // Determine file extension
        const fileExtension =
            extension || (contentType ? contentType.split('/')[1] : type);

        // Try to get filename from Content-Disposition header
        const dispositionHeader = response.headers.get('content-disposition');
        const filenameMatch = dispositionHeader?.match(/filename[^;=\n]*=((['"]).*?\2|[^;\n]*)/);

        // Extract filename from URL as fallback
        const urlFilename = url.split('/').pop().split('?')[0]; // Remove query params
        const decodedUrlFilename = decodeURIComponent(urlFilename);

        const filename =
            filenameMatch?.[1]?.replace(/['"]/g, '') ||
            (decodedUrlFilename && decodedUrlFilename !== url ? decodedUrlFilename : `attachment_${Date.now()}.${fileExtension}`);

        // Create blob URL and download
        const blobUrl = URL.createObjectURL(blobData);
        const link = Object.assign(document.createElement('a'), {
            href: blobUrl,
            download: filename,
            style: 'display: none',
        });

        document.body.append(link);
        link.click();
        link.remove();

        // Clean up blob URL after a short delay to ensure download starts
        setTimeout(() => {
            URL.revokeObjectURL(blobUrl);
        }, 100);
    } catch (error) {
        // Enhanced error handling for CORS and network issues
        if (error.name === 'TypeError' && error.message.includes('fetch')) {
            throw new Error('Download failed: Network error or CORS policy blocked the request');
        }
        throw error instanceof Error ? error : new Error('Download failed');
    }
};
