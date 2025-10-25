# NeuroVision Backend Deployment Guide

## Prerequisites
1. A Render.com account (free tier available)
2. A MongoDB Atlas database (free tier available)
3. Git installed on your local machine

## Deployment Steps

### 1. Set up MongoDB Atlas
1. Go to [MongoDB Atlas](https://www.mongodb.com/cloud/atlas) and create a free account if you don't have one
2. Create a new project and a free shared cluster
3. Create a database user and note down the credentials
4. Add your current IP address to the IP whitelist
5. Get the connection string (it will look like `mongodb+srv://<username>:<password>@<cluster>.mongodb.net/`)

### 2. Deploy to Render

#### Option A: Using Render Dashboard
1. Go to [Render Dashboard](https://dashboard.render.com/)
2. Click "New" and select "Web Service"
3. Connect your GitHub/GitLab repository or use the public repository URL
4. Configure the service:
   - Name: `neurovision-backend`
   - Region: Choose the one closest to your users
   - Branch: `main` or your preferred branch
   - Root Directory: `backend`
   - Build Command: `pip install -r requirements.txt`
   - Start Command: `gunicorn app:app --bind 0.0.0.0:$PORT`
   - Plan: Free

5. Add environment variables:
   - `MONGO_URI`: Your MongoDB connection string (add your database name at the end, e.g., `...mongodb.net/neurovision`)
   - `DETECTION_API_KEY`: A secure random string (you can generate one with `openssl rand -hex 16`)
   - `ALLOWED_ORIGINS`: Your frontend URL or `*` for development
   - `PYTHON_VERSION`: `3.11.5`

6. Click "Create Web Service"

#### Option B: Using Render CLI
1. Install Render CLI: `npm install -g render-cli`
2. Login: `render login`
3. Deploy: `render.yaml` is already configured in the repository
4. Run: `render deploy`

### 3. Verify Deployment
1. Once deployed, visit `https://your-app-name.onrender.com/health` to verify the API is running
2. You should see a JSON response with the service status

## API Endpoints

### Session Management
- `POST /api/sessions/start` - Start a new recording session
  - Request body: `{"metadata": {"user_id": "123", "device": "mobile"}}`
  - Response: `{"session_id": "...", "status": "started", "start_time": "..."}`

- `POST /api/sessions/<session_id>/end` - End a recording session
  - Response: `{"session_id": "...", "status": "completed", "end_time": "..."}`

- `POST /api/sessions/<session_id>/detect` - Process a frame (same as /detect but with session tracking)
  - Accepts multipart form-data or JSON with dataUrl
  - Response: Same as /detect but also saves to session

- `GET /api/sessions/<session_id>` - Get session details
  - Response: Session metadata and detection count

### Face Detection
- `POST /detect` - Process a single image
  - Accepts multipart form-data (`image` file) or JSON `{"dataUrl": "data:image/jpeg;base64,..."}`
  - Response: `{"landmarks": [x0,y0,x1,y1,...], "width": W, "height": H}`

## Frontend Integration

### Starting a Session
```javascript
async function startSession() {
  const response = await fetch('https://your-app-name.onrender.com/api/sessions/start', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${API_KEY}`
    },
    body: JSON.stringify({
      metadata: {
        user_id: 'user123',
        device: 'mobile',
        // Add any other metadata
      }
    })
  });
  return await response.json();
}
```

### Sending Frames
```javascript
async function sendFrame(sessionId, imageData) {
  const formData = new FormData();
  formData.append('image', imageData);
  
  const response = await fetch(`https://your-app-name.onrender.com/api/sessions/${sessionId}/detect`, {
    method: 'POST',
    headers: {
      'Authorization': `Bearer ${API_KEY}`
    },
    body: formData
  });
  return await response.json();
}
```

## Troubleshooting

### Common Issues
1. **MongoDB Connection Failed**
   - Verify your MongoDB connection string
   - Check if your IP is whitelisted in MongoDB Atlas
   - Ensure the database user has proper permissions

2. **MediaPipe Not Working**
   - Make sure you're using the correct Python version (3.11.5 recommended)
   - Check the logs for any build errors during deployment

3. **CORS Issues**
   - Make sure `ALLOWED_ORIGINS` is set correctly
   - Include protocol in the URL (e.g., `https://your-frontend.com`)

### Viewing Logs
1. Go to your Render dashboard
2. Select your service
3. Click on the "Logs" tab to view real-time logs

## Security Considerations
1. **Never** commit your API keys or MongoDB URI to version control
2. Use HTTPS for all API requests
3. Implement rate limiting in production
4. Regularly rotate your API keys
5. Monitor your MongoDB Atlas dashboard for unusual activity

## Scaling
For production use with many concurrent users:
1. Upgrade to a paid plan on Render
2. Use MongoDB Atlas M0+ for better performance
3. Implement connection pooling
4. Consider adding a CDN for static assets
5. Monitor performance and scale resources as needed
