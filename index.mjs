/**
 * LOX24 Custom SMS Sender for AWS Cognito
 * 
 * This Lambda function integrates AWS Cognito User Pools with LOX24 SMS Gateway.
 * It handles all Cognito SMS trigger events and sends messages via LOX24 API.
 * 
 * Required Environment Variables:
 * - LOX24_AUTH_TOKEN: Your LOX24 API authentication token
 * - LOX24_SENDER_ID: Default sender ID for SMS messages
 * - KMS_KEY_ID: AWS KMS Key ID for decryption
 * - KMS_KEY_ARN: AWS KMS Key ARN for decryption
 * 
 * Optional Environment Variables:
 * - LOX24_API_HOST: LOX24 API hostname (default: api.lox24.eu)
 * - LOX24_SERVICE_CODE: Service code (default: direct)
 * - ENABLE_DEBUG_LOGGING: Set to 'true' for detailed logs (default: false)
 */

import { KmsKeyringNode, buildClient, CommitmentPolicy } from '@aws-crypto/client-node';
import https from 'https';

// Configure the encryption SDK client with KMS key from environment variables
const { decrypt } = buildClient(
    CommitmentPolicy.REQUIRE_ENCRYPT_ALLOW_DECRYPT
);

// Environment variables
const LOX24_AUTH_TOKEN = process.env.LOX24_AUTH_TOKEN;
const LOX24_SENDER_ID = process.env.LOX24_SENDER_ID;
const LOX24_API_HOST = process.env.LOX24_API_HOST || 'api.lox24.eu';
const LOX24_SERVICE_CODE = process.env.LOX24_SERVICE_CODE || 'direct';
const ENABLE_DEBUG_LOGGING = process.env.ENABLE_DEBUG_LOGGING === 'true';

// Validate required environment variables
if (!LOX24_AUTH_TOKEN) {
    throw new Error('LOX24_AUTH_TOKEN environment variable is required');
}
if (!LOX24_SENDER_ID) {
    throw new Error('LOX24_SENDER_ID environment variable is required');
}
if (!process.env.KMS_KEY_ID) {
    throw new Error('KMS_KEY_ID environment variable is required');
}
if (!process.env.KMS_KEY_ARN) {
    throw new Error('KMS_KEY_ARN environment variable is required');
}

const generatorKeyId = process.env.KMS_KEY_ID;
const keyIds = [process.env.KMS_KEY_ARN];
const keyring = new KmsKeyringNode({ generatorKeyId, keyIds });

/**
 * Sends SMS via LOX24 API
 * 
 * @param {string} phoneNumber - Recipient phone number in E.164 format
 * @param {string} message - SMS message text
 * @param {object} options - Additional options
 * @returns {Promise<object>} - API response
 */
const sendSmsViaLox24 = async (phoneNumber, message, options = {}) => {
    const postObj = {
        sender_id: options.senderId || LOX24_SENDER_ID,
        text: message,
        service_code: options.serviceCode || LOX24_SERVICE_CODE,
        phone: phoneNumber,
        is_unicode: containsUnicode(message),
        ...(options.callbackData && { callback_data: options.callbackData }),
        ...(options.deliveryAt && { delivery_at: options.deliveryAt }),
        ...(options.voiceLang && { voice_lang: options.voiceLang })
    };

    const postData = JSON.stringify(postObj);

    if (ENABLE_DEBUG_LOGGING) {
        console.log('LOX24 API Request:', {
            ...postObj,
            phone: maskPhoneNumber(phoneNumber),
            text: maskCode(message)
        });
    }

    return new Promise((resolve, reject) => {
        const requestOptions = {
            hostname: LOX24_API_HOST,
            path: '/sms',
            method: 'POST',
            headers: {
                'Accept': 'application/json',
                'Content-Type': 'application/json',
                'Content-Length': Buffer.byteLength(postData),
                'X-LOX24-AUTH-TOKEN': LOX24_AUTH_TOKEN
            },
            timeout: 10000 // 10 second timeout
        };

        const req = https.request(requestOptions, (res) => {
            let responseData = '';

            res.on('data', (chunk) => {
                responseData += chunk;
            });

            res.on('end', () => {
                if (res.statusCode === 201) {
                    console.log(`SMS sent successfully to ${maskPhoneNumber(phoneNumber)}`);
                    if (ENABLE_DEBUG_LOGGING) {
                        console.log('LOX24 API Response:', responseData);
                    }
                    try {
                        resolve({
                            success: true,
                            statusCode: res.statusCode,
                            data: JSON.parse(responseData)
                        });
                    } catch (e) {
                        resolve({
                            success: true,
                            statusCode: res.statusCode,
                            data: responseData
                        });
                    }
                } else {
                    const errorMessage = getErrorMessage(res.statusCode);
                    console.error(`LOX24 API Error: ${errorMessage} (Status: ${res.statusCode})`);
                    console.error('Response:', responseData);
                    reject(new Error(`${errorMessage} (HTTP ${res.statusCode})`));
                }
            });
        });

        req.on('error', (error) => {
            console.error('LOX24 API Request Error:', error);
            reject(error);
        });

        req.on('timeout', () => {
            req.destroy();
            reject(new Error('LOX24 API request timeout'));
        });

        req.write(postData);
        req.end();
    });
};

/**
 * Decrypts the code from Cognito using AWS KMS
 * 
 * @param {string} encryptedCode - Base64 encoded encrypted code
 * @returns {Promise<string>} - Decrypted plaintext code
 */
const decryptCode = async (encryptedCode) => {
    if (!encryptedCode) {
        throw new Error('No code provided to decrypt');
    }

    try {
        const { plaintext } = await decrypt(
            keyring,
            Buffer.from(encryptedCode, 'base64')
        );
        return Buffer.from(plaintext).toString('utf-8');
    } catch (error) {
        console.error('Error decrypting code:', error);
        throw new Error('Failed to decrypt verification code');
    }
};

/**
 * Generates appropriate SMS message based on trigger source
 * 
 * @param {string} triggerSource - Cognito trigger source
 * @param {string} code - Verification code
 * @param {object} userAttributes - User attributes from Cognito
 * @returns {string} - Formatted SMS message
 */
const generateMessage = (triggerSource, code, userAttributes) => {
    const username = userAttributes.name || userAttributes.email || 'User';
    
    switch (triggerSource) {
        case 'CustomSMSSender_SignUp':
            return `Welcome to our service! Your verification code is: ${code}`;
        
        case 'CustomSMSSender_ForgotPassword':
            return `Your password reset code is: ${code}. If you didn't request this, please ignore this message.`;
        
        case 'CustomSMSSender_ResendCode':
            return `Your verification code is: ${code}`;
        
        case 'CustomSMSSender_VerifyUserAttribute':
            return `Your verification code is: ${code}`;
        
        case 'CustomSMSSender_UpdateUserAttribute':
            return `Your verification code to update your phone number is: ${code}`;
        
        case 'CustomSMSSender_Authentication':
            return `Your authentication code is: ${code}. This code will expire in 3 minutes.`;
        
        case 'CustomSMSSender_AdminCreateUser':
            return `Welcome! Your temporary password is: ${code}. Please change it after your first login.`;
        
        default:
            return `Your verification code is: ${code}`;
    }
};

/**
 * Main Lambda handler
 * 
 * @param {object} event - Cognito Custom SMS Sender event
 * @returns {Promise<object>} - Lambda response
 */
export const handler = async (event) => {
    console.log('Received Cognito Custom SMS Sender event:', {
        triggerSource: event.triggerSource,
        userPoolId: event.userPoolId,
        userName: event.userName
    });

    if (ENABLE_DEBUG_LOGGING) {
        console.log('Full event:', JSON.stringify(event, null, 2));
    }

    try {
        // Validate event structure
        if (!event.request || event.request.type !== 'customSMSSenderRequestV1') {
            throw new Error('Invalid event type. Expected customSMSSenderRequestV1');
        }

        // Extract user attributes
        const userAttributes = event.request.userAttributes || {};
        const phoneNumber = userAttributes.phone_number;

        if (!phoneNumber) {
            throw new Error('No phone number found in user attributes');
        }

        // Decrypt the verification code
        let plainTextCode = null;
        if (event.request.code) {
            plainTextCode = await decryptCode(event.request.code);
        }

        // Generate appropriate message based on trigger source
        const message = generateMessage(
            event.triggerSource,
            plainTextCode,
            userAttributes
        );

        // Prepare options for LOX24 API
        const sendOptions = {
            callbackData: event.userName // Use Cognito username as callback data for tracking
        };

        // Check for custom metadata (can be used to override settings)
        if (event.request.clientMetadata) {
            if (event.request.clientMetadata.senderId) {
                sendOptions.senderId = event.request.clientMetadata.senderId;
            }
            if (event.request.clientMetadata.voiceLang) {
                sendOptions.voiceLang = event.request.clientMetadata.voiceLang;
            }
        }

        // Send SMS via LOX24
        const result = await sendSmsViaLox24(phoneNumber, message, sendOptions);

        console.log(`Successfully processed ${event.triggerSource} for user ${event.userName}`);

        // Return success (Cognito doesn't expect specific response data)
        return {
            statusCode: 200,
            body: JSON.stringify({
                success: true,
                message: 'SMS sent successfully via LOX24'
            })
        };

    } catch (error) {
        console.error('Error in Custom SMS Sender Lambda:', error);
        
        // Log additional context for debugging
        console.error('Error context:', {
            triggerSource: event.triggerSource,
            userName: event.userName,
            errorMessage: error.message,
            errorStack: error.stack
        });

        // Re-throw error so Cognito knows the operation failed
        throw error;
    }
};

/**
 * Helper function to check if string contains Unicode characters
 * 
 * @param {string} str - String to check
 * @returns {boolean} - True if contains Unicode
 */
const containsUnicode = (str) => {
    for (let i = 0; i < str.length; i++) {
        if (str.charCodeAt(i) > 127) {
            return true;
        }
    }
    return false;
};

/**
 * Masks phone number for logging (security)
 * 
 * @param {string} phoneNumber - Phone number to mask
 * @returns {string} - Masked phone number
 */
const maskPhoneNumber = (phoneNumber) => {
    if (!phoneNumber || phoneNumber.length < 4) {
        return '****';
    }
    return phoneNumber.substring(0, 3) + '*'.repeat(phoneNumber.length - 6) + phoneNumber.substring(phoneNumber.length - 3);
};

/**
 * Masks verification codes in messages for logging (security)
 * 
 * @param {string} message - Message to mask
 * @returns {string} - Message with codes masked
 */
const maskCode = (message) => {
    return message.replace(/\b\d{4,8}\b/g, '****');
};

/**
 * Maps HTTP status codes to error messages
 * 
 * @param {number} statusCode - HTTP status code
 * @returns {string} - Error message
 */
const getErrorMessage = (statusCode) => {
    const errorMessages = {
        400: 'Invalid input - Check phone number format and message content',
        401: 'Authentication failed - LOX24 API token is invalid or inactive',
        402: 'Insufficient funds - Please add credit to your LOX24 account',
        403: 'Account not activated - Please contact LOX24 support',
        404: 'API endpoint not found',
        429: 'Rate limit exceeded - Too many requests',
        500: 'LOX24 API internal error',
        503: 'LOX24 API temporarily unavailable'
    };
    
    return errorMessages[statusCode] || `Unexpected error from LOX24 API`;
};
