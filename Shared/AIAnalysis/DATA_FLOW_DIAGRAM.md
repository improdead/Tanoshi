# Complete Data Flow: iOS ↔ Google Colab

## 🔄 **Step-by-Step Data Flow**

### **1. PDF Import & Processing (iOS Side)**

```swift
// User imports PDF manga
LocalFileManager.uploadFile(from: pdfURL, mangaId: "one-piece", chapterId: "chapter-1")

// Automatic analysis triggers
AIAnalysisManager.analyzeChapterAutomatically(mangaId: "one-piece", chapterId: "chapter-1")

// PDF pages extracted
let pages = try await extractPagesFromPDF(pdfURL)
// Result: [UIImage, UIImage, UIImage...] - one per page
```

### **2. Image Conversion (iOS Side)**

```swift
// Convert UIImages to base64 for HTTP transmission
private func convertImagesToBase64(_ images: [UIImage]) async throws -> [String] {
    return try await withThrowingTaskGroup(of: String?.self) { group in
        for image in images {
            group.addTask {
                guard let pngData = image.pngData() else { return nil }
                return pngData.base64EncodedString() // Convert to base64
            }
        }
        // Collect all base64 strings
        var base64Images: [String] = []
        for try await base64String in group {
            if let base64String = base64String {
                base64Images.append(base64String)
            }
        }
        return base64Images
    }
}
```

### **3. HTTP Request Preparation (iOS Side)**

```swift
// Prepare JSON payload
let requestBody: [String: Any] = [
    "pages": [
        "iVBORw0KGgoAAAANSUhEUgAA...", // base64 page 1
        "iVBORw0KGgoAAAANSUhEUgAA...", // base64 page 2
        "iVBORw0KGgoAAAANSUhEUgAA..."  // base64 page 3
    ],
    "characterBank": {
        "images": ["iVBORw0KGgoAAAANSUhEUgAA..."], // base64 character refs
        "names": ["Luffy", "Zoro", "Sanji"]
    }
}

// Send POST request to Colab
POST https://abc123.ngrok.io/analyze
Content-Type: application/json
Body: JSON payload above
```

### **4. Request Reception (Colab Side)**

```python
@app.route('/analyze', methods=['POST'])
def analyze_manga():
    """Receive manga pages and start analysis"""
    try:
        data = request.json
        
        # Extract data
        pages_b64 = data['pages']  # Array of base64 strings
        character_bank = data.get('characterBank', {"images": [], "names": []})
        
        # Convert base64 to numpy arrays
        chapter_pages = []
        for page_b64 in pages_b64:
            img = read_image_from_base64(page_b64)  # base64 → PIL → numpy
            if img is not None:
                chapter_pages.append(img)
        
        # Create background job
        job_id = create_job_id()  # Generate UUID
        analysis_jobs[job_id] = AnalysisJob(job_id)
        
        # Start processing in background thread
        thread = threading.Thread(
            target=process_manga_analysis,
            args=(job_id, chapter_pages, character_bank)
        )
        thread.start()
        
        # Return job ID immediately
        return jsonify({
            "job_id": job_id,
            "status": "started",
            "message": f"Analysis started for {len(chapter_pages)} pages"
        })
        
    except Exception as e:
        return jsonify({"error": str(e)}), 500
```

### **5. AI Processing (Colab Side)**

```python
def process_manga_analysis(job_id: str, chapter_pages: List[np.ndarray], character_bank: Dict[str, Any]):
    """Background processing with MagiV2"""
    job = analysis_jobs[job_id]
    
    try:
        job.status = "processing"
        job.progress = 0.1
        
        # Prepare character bank
        character_images = []
        character_names = character_bank.get("names", [])
        
        for img_b64 in character_bank.get("images", []):
            img = read_image_from_base64(img_b64)
            if img is not None:
                character_images.append(img)
        
        character_bank_processed = {
            "images": character_images,
            "names": character_names
        }
        
        job.progress = 0.2
        
        # Run MagiV2 analysis
        with torch.no_grad():
            per_page_results = magi_model.do_chapter_wide_prediction(
                chapter_pages,           # numpy arrays of manga pages
                character_bank_processed, # character reference images
                use_tqdm=True, 
                do_ocr=True             # Extract text from speech bubbles
            )
        
        job.progress = 0.8
        
        # Process results into JSON format
        transcript = []
        pages_analysis = []
        
        for i, (image, page_result) in enumerate(zip(chapter_pages, per_page_results)):
            # Map text to characters
            speaker_name = {
                text_idx: page_result["character_names"][char_idx] 
                for text_idx, char_idx in page_result["text_character_associations"]
            }
            
            # Extract text regions with bounding boxes
            text_regions = []
            for j, text in enumerate(page_result["ocr"]):
                if page_result["is_essential_text"][j]:
                    text_regions.append({
                        "id": j,
                        "text": text,
                        "boundingBox": convert_bbox(page_result["text_bboxes"][j]),
                        "confidence": 1.0,
                        "isEssential": True
                    })
                    
                    # Add to transcript
                    speaker = speaker_name.get(j, "unknown")
                    transcript.append({
                        "pageIndex": i,
                        "textId": j,
                        "speaker": speaker,
                        "text": text,
                        "timestamp": None
                    })
            
            # Extract character detections
            character_detections = []
            for char_idx, char_name in enumerate(page_result["character_names"]):
                character_detections.append({
                    "id": char_idx,
                    "name": char_name,
                    "boundingBox": convert_bbox(page_result["character_bboxes"][char_idx]),
                    "confidence": 1.0
                })
            
            pages_analysis.append({
                "pageIndex": i,
                "textRegions": text_regions,
                "characterDetections": character_detections,
                "textCharacterAssociations": page_result["text_character_associations"]
            })
        
        # Store final result
        result = {
            "pages": pages_analysis,
            "transcript": transcript,
            "analysisDate": time.time(),
            "version": "1.0"
        }
        
        job.result = result
        job.status = "completed"
        job.progress = 1.0
        
    except Exception as e:
        job.status = "failed"
        job.error = str(e)
```

### **6. Status Polling (iOS Side)**

```swift
// iOS polls for completion
private func pollAnalysisCompletion(jobId: String, cacheKey: String) async throws -> AnalysisResult {
    let maxAttempts = 60 // 5 minutes
    let pollInterval: TimeInterval = 5.0
    
    for attempt in 0..<maxAttempts {
        // Check status
        let response = try await colabClient.getAnalysisStatus(jobId: jobId)
        
        switch response.status {
        case "completed":
            // Get final result
            return try await colabClient.getAnalysisResult(jobId: jobId)
        case "processing", "pending":
            // Wait and try again
            try await Task.sleep(nanoseconds: UInt64(pollInterval * 1_000_000_000))
        case "failed":
            throw AIAnalysisError.invalidResponse
        }
    }
    
    throw AIAnalysisError.analysisTimeout
}
```

### **7. Result Retrieval (Colab → iOS)**

```python
@app.route('/result/<job_id>', methods=['GET'])
def get_analysis_result(job_id):
    """Return completed analysis result"""
    if job_id not in analysis_jobs:
        return jsonify({"error": "Job not found"}), 404
    
    job = analysis_jobs[job_id]
    
    if job.status != "completed":
        return jsonify({
            "error": "Job not completed",
            "status": job.status,
            "progress": job.progress
        }), 400
    
    # Return the processed result
    return jsonify(job.result)
```

**Example Response JSON:**
```json
{
  "pages": [
    {
      "pageIndex": 0,
      "textRegions": [
        {
          "id": 0,
          "text": "I'm gonna be the Pirate King!",
          "boundingBox": {"x": 100, "y": 200, "width": 300, "height": 50},
          "confidence": 1.0,
          "isEssential": true
        }
      ],
      "characterDetections": [
        {
          "id": 0,
          "name": "Luffy",
          "boundingBox": {"x": 50, "y": 100, "width": 200, "height": 400},
          "confidence": 1.0
        }
      ],
      "textCharacterAssociations": {"0": 0}
    }
  ],
  "transcript": [
    {
      "pageIndex": 0,
      "textId": 0,
      "speaker": "Luffy",
      "text": "I'm gonna be the Pirate King!",
      "timestamp": null
    }
  ],
  "analysisDate": 1703123456.789,
  "version": "1.0"
}
```

### **8. Local Caching (iOS Side)**

```swift
// Cache result locally
await cacheManager.cacheAnalysisResult(result, mangaId: mangaId, chapterId: chapterId)

// Store in Core Data for offline access
await coreDataManager.saveAnalysisResult(result)

// Result now available offline
let cachedResult = await cacheManager.getCachedResult(mangaId: mangaId, chapterId: chapterId)
```

### **9. Audio Generation (Optional)**

```swift
// Generate audio from transcript
let audioSegments = try await aiManager.generateAudio(mangaId: mangaId, chapterId: chapterId)

// Start playbook with auto page turning
await audioManager.playTranscript(audioSegments, transcript: result.transcript)
```

## 🌐 **Network Architecture**

```
┌─────────────────┐    HTTP POST     ┌─────────────────┐
│   iOS App       │ ───────────────► │  Google Colab   │
│                 │                  │                 │
│ • PDF Extract   │                  │ • MagiV2 Model  │
│ • Base64 Encode │                  │ • XTTS-v2 TTS   │
│ • HTTP Client   │                  │ • Flask Server  │
│ • Local Cache   │                  │ • ngrok Tunnel  │
│                 │ ◄─────────────── │                 │
└─────────────────┘    JSON Result   └─────────────────┘
```

## 🔧 **Configuration**

**iOS Configuration:**
```swift
let config = ColabConfiguration(
    endpointURL: URL(string: "https://abc123.ngrok.io")!, // Your ngrok URL
    apiKey: nil,
    timeout: 300.0,
    maxRetries: 3,
    batchSize: 10
)
```

**Colab Setup:**
1. Run all cells in the setup notebook
2. Copy the ngrok URL from the output
3. Paste URL into iOS app settings
4. System automatically connects and processes manga

## ⚡ **Performance Notes**

- **Image Size**: Pages are resized to ~800x1200 for optimal processing
- **Batch Processing**: Multiple pages sent in single request
- **Background Jobs**: Analysis runs asynchronously with progress tracking
- **Caching**: Results cached locally for instant offline access
- **Memory Management**: Temporary files cleaned up automatically

This complete flow ensures seamless integration between your iOS manga reader and the Google Colab AI backend!