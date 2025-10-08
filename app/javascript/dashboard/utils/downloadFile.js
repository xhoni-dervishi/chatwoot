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
        const response = await fetch(url, { cache: 'no-store' });

        if (!response.ok) {
            throw new Error(`Download failed: ${response.status}`);
        }

        const blobData = await response.blob();

        const contentType = response.headers.get('content-type');

        const fileExtension =
            extension || (contentType ? contentType.split('/')[1] : type);

        const dispositionHeader = response.headers.get('content-disposition');
        const filenameMatch = dispositionHeader?.match(/filename="(.*?)"/);

        const filename =
            filenameMatch?.[1] ?? `attachment_${Date.now()}.${fileExtension}`;

        const blobUrl = URL.createObjectURL(blobData);
        const link = Object.assign(document.createElement('a'), {
            href: blobUrl,
            download: filename,
            style: 'display: none',
        });

        document.body.append(link);
        link.click();
        link.remove();
        URL.revokeObjectURL(blobUrl);
    } catch (error) {
        throw error instanceof Error ? error : new Error('Download failed');
    }
};
