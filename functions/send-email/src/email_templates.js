/**
 * Email Templates for CRADI Mobile
 * 
 * HTML email templates with CRADI branding for various notification types
 */

const templates = {
    /**
     * Email Verification Template
     * Sends OTP code for login verification
     */
    verification: (data) => ({
        subject: `Your CRADI Verification Code: ${data.code}`,
        html: `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
      </head>
      <body style="margin: 0; padding: 20px; font-family: Arial, sans-serif; background-color: #f5f5f5;">
        <div style="max-width: 600px; margin: 0 auto; background-color: white; border-radius: 8px; overflow: hidden;">
          <!-- Header -->
          <div style="background: linear-gradient(135deg, #C62828 0%, #B71C1C 100%); padding: 30px; text-align: center;">
            <h1 style="color: white; margin: 0; font-size: 24px;">CRADI Mobile</h1>
            <p style="color: white; margin: 5px 0 0 0; opacity: 0.9;">Early Warning System</p>
          </div>
          
          <!-- Content -->
          <div style="padding: 40px 30px;">
            <h2 style="color: #333; margin-top: 0;">Verification Code</h2>
            <p style="color: #666; line-height: 1.6;">Hello ${data.name || 'User'},</p>
            <p style="color: #666; line-height: 1.6;">Your verification code is:</p>
            
            <!-- OTP Code -->
            <div style="background-color: #f5f5f5; border-left: 4px solid #C62828; padding: 20px; margin: 30px 0; text-align: center;">
              <h1 style="color: #C62828; font-size: 42px; margin: 0; letter-spacing: 8px; font-family: 'Courier New', monospace;">${data.code}</h1>
            </div>
            
            <p style="color: #999; font-size: 14px; line-height: 1.6;">
              This code will expire in <strong>10 minutes</strong>. Do not share this code with anyone.
            </p>
          </div>
          
          <!-- Footer -->
          <div style="background-color: #f9f9f9; padding: 20px 30px; text-align: center; border-top: 1px solid #e0e0e0;">
            <p style="color: #999; font-size: 12px; margin: 0;">
              This is an automated message from CRADI Mobile. Please do not reply to this email.
            </p>
          </div>
        </div>
      </body>
      </html>
    `
    }),

    /**
     * Alert Notification Template
     * Sends hazard alerts to authorities
     */
    alert: (data) => ({
        subject: `🚨 ${data.severity.toUpperCase()} Alert: ${data.hazardType} in ${data.lga}`,
        html: `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
      </head>
      <body style="margin: 0; padding: 20px; font-family: Arial, sans-serif; background-color: #f5f5f5;">
        <div style="max-width: 600px; margin: 0 auto; background-color: white; border-radius: 8px; overflow: hidden; border: 3px solid #C62828;">
          <!-- Alert Header -->
          <div style="background-color: #C62828; padding: 20px; text-align: center;">
            <h1 style="color: white; margin: 0; font-size: 32px;">⚠️ EMERGENCY ALERT</h1>
          </div>
          
          <!-- Alert Content -->
          <div style="padding: 30px;">
            <div style="background-color: #fff3e0; border-left: 4px solid #ff9800; padding: 15px; margin-bottom: 20px;">
              <p style="margin: 0; color: #e65100; font-weight: bold;">ACTION REQUIRED: Climate Hazard Detected</p>
            </div>
            
            <table style="width: 100%; border-collapse: collapse;">
              <tr>
                <td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #666; font-weight: bold; width: 30%;">Hazard Type:</td>
                <td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #333;">${data.hazardType}</td>
              </tr>
              <tr>
                <td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #666; font-weight: bold;">Severity:</td>
                <td style="padding: 12px; border-bottom: 1px solid #e0e0e0;">
                  <span style="background-color: ${data.severity === 'Critical' ? '#d32f2f' : data.severity === 'High' ? '#ff9800' : '#fbc02d'}; color: white; padding: 4px 12px; border-radius: 4px; font-weight: bold;">
                    ${data.severity.toUpperCase()}
                  </span>
                </td>
              </tr>
              <tr>
                <td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #666; font-weight: bold;">Location:</td>
                <td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #333;">${data.ward}, ${data.lga}</td>
              </tr>
              <tr>
                <td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #666; font-weight: bold;">State:</td>
                <td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #333;">${data.state}</td>
              </tr>
              <tr>
                <td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #666; font-weight: bold;">Reported:</td>
                <td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #333;">${data.timestamp}</td>
              </tr>
            </table>
            
            <div style="margin-top: 20px; padding: 20px; background-color: #f5f5f5; border-radius: 4px;">
              <h3 style="margin-top: 0; color: #333;">Description:</h3>
              <p style="color: #666; line-height: 1.6; margin: 0;">${data.description}</p>
            </div>

            ${data.recommendations ? `
            <div style="margin-top: 20px; padding: 20px; background-color: #e8f5e9; border-left: 4px solid #4caf50; border-radius: 4px;">
              <h3 style="margin-top: 0; color: #2e7d32;">Safety Recommendations:</h3>
              <p style="color: #1b5e20; line-height: 1.6; margin: 0;">${data.recommendations}</p>
            </div>
            ` : ''}
          </div>
          
          <!-- Footer -->
          <div style="background-color: #f9f9f9; padding: 20px 30px; text-align: center; border-top: 1px solid #e0e0e0;">
            <p style="color: #666; font-size: 14px; margin: 0;">
              <strong>CRADI Mobile - Climate Resilience and Development Initiative</strong>
            </p>
            <p style="color: #999; font-size: 12px; margin: 10px 0 0 0;">
              This alert was generated automatically by the Early Warning System
            </p>
          </div>
        </div>
      </body>
      </html>
    `
    }),

    /**
     * Status Update Template
     * Notifies users when their report status changes
     */
    statusUpdate: (data) => ({
        subject: `Report Update: ${data.status} - ${data.hazardType}`,
        html: `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
      </head>
      <body style="margin: 0; padding: 20px; font-family: Arial, sans-serif; background-color: #f5f5f5;">
        <div style="max-width: 600px; margin: 0 auto; background-color: white; border-radius: 8px; overflow: hidden;">
          <!-- Header -->
          <div style="background: linear-gradient(135deg, #C62828 0%, #B71C1C 100%); padding: 30px; text-align: center;">
            <h1 style="color: white; margin: 0; font-size: 24px;">Report Status Update</h1>
          </div>
          
          <!-- Content -->
          <div style="padding: 30px;">
            <p style="color: #666; line-height: 1.6;">Hello ${data.reporterName || 'User'},</p>
            <p style="color: #666; line-height: 1.6;">Your hazard report has been updated:</p>
            
            <table style="width: 100%; border-collapse: collapse; margin: 20px 0;">
              <tr>
                <td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #666; font-weight: bold;">Report ID:</td>
                <td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #333; font-family: monospace;">${data.reportId}</td>
              </tr>
              <tr>
                <td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #666; font-weight: bold;">Hazard Type:</td>
                <td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #333;">${data.hazardType}</td>
              </tr>
              <tr>
                <td style="padding: 12px; border-bottom: 1px solid #e0e0e0; color: #666; font-weight: bold;">New Status:</td>
                <td style="padding: 12px; border-bottom: 1px solid #e0e0e0;">
                  <span style="background-color: ${data.status === 'Validated' ? '#4caf50' : data.status === 'Resolved' ? '#2196f3' : '#ff9800'}; color: white; padding: 4px 12px; border-radius: 4px; font-weight: bold;">
                    ${data.status.toUpperCase()}
                  </span>
                </td>
              </tr>
            </table>

            ${data.comments ? `
            <div style="margin-top: 20px; padding: 20px; background-color: #f5f5f5; border-radius: 4px;">
              <h3 style="margin-top: 0; color: #333;">Comments from Coordinator:</h3>
              <p style="color: #666; line-height: 1.6; margin: 0;">${data.comments}</p>
            </div>
            ` : ''}
            
            <p style="color: #666; line-height: 1.6; margin-top: 20px;">
              Thank you for helping keep our communities safe through the CRADI Early Warning System.
            </p>
          </div>
          
          <!-- Footer -->
          <div style="background-color: #f9f9f9; padding: 20px 30px; text-align: center; border-top: 1px solid #e0e0e0;">
            <p style="color: #999; font-size: 12px; margin: 0;">
              CRADI Mobile - Early Warning System
            </p>
          </div>
        </div>
      </body>
      </html>
    `
    }),

    /**
     * Welcome Email Template
     * Sent to new users upon registration
     */
    welcome: (data) => ({
        subject: 'Welcome to CRADI Mobile - Early Warning System',
        html: `
      <!DOCTYPE html>
      <html>
      <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
      </head>
      <body style="margin: 0; padding: 20px; font-family: Arial, sans-serif; background-color: #f5f5f5;">
        <div style="max-width: 600px; margin: 0 auto; background-color: white; border-radius: 8px; overflow: hidden;">
          <!-- Header -->
          <div style="background: linear-gradient(135deg, #C62828 0%, #B71C1C 100%); padding: 40px; text-align: center;">
            <h1 style="color: white; margin: 0; font-size: 28px;">Welcome to CRADI!</h1>
            <p style="color: white; margin: 10px 0 0 0; opacity: 0.9;">Climate Resilience & Development Initiative</p>
          </div>
          
          <!-- Content -->
          <div style="padding: 40px 30px;">
            <h2 style="color: #333; margin-top: 0;">Hello ${data.name}! 👋</h2>
            <p style="color: #666; line-height: 1.6;">
              Thank you for joining the CRADI Mobile Early Warning System. Your account has been successfully created.
            </p>
            
            <div style="background-color: #e3f2fd; padding: 20px; border-radius: 4px; margin: 20px 0;">
              <p style="margin: 0; color: #1976d2;"><strong>Your Role:</strong> ${data.role}</p>
              <p style="margin: 10px 0 0 0; color: #1976d2;"><strong>Email:</strong> ${data.email}</p>
            </div>
            
            <h3 style="color: #333;">What you can do:</h3>
            <ul style="color: #666; line-height: 1.8;">
              <li>Report climate hazards in your area</li>
              <li>Track the status of your reports</li>
              <li>Receive real-time alerts about validated hazards</li>
              <li>Access knowledge base and safety resources</li>
              <li>Connect with emergency authorities</li>
            </ul>
            
            <div style="text-align: center; margin: 30px 0;">
              <p style="color: #666; margin-bottom: 15px;">Get started by logging into the mobile app</p>
            </div>
          </div>
          
          <!-- Footer -->
          <div style="background-color: #f9f9f9; padding: 20px 30px; text-align: center; border-top: 1px solid #e0e0e0;">
            <p style="color: #666; font-size: 14px; margin: 0;">
              <strong>Need Help?</strong>
            </p>
            <p style="color: #999; font-size: 12px; margin: 10px 0 0 0;">
              Contact your local coordinator or visit the knowledge base in the app
            </p>
          </div>
        </div>
      </body>
      </html>
    `
    })
};

module.exports = templates;
