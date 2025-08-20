//
//  ConnectionTest.swift
//  Aidoku
//
//  Created by AI Analysis Feature - Connection Testing
//

import Foundation
import UIKit

/// Simple test to verify iOS ↔ Colab connection
class AIAnalysisConnectionTest {
    
    static func testConnection() async {
        print("🧪 Testing AI Analysis Connection...")
        
        let configManager = AIAnalysisConfigManager.shared
        let colabClient = ColabAPIClient.shared
        
        // Step 1: Check configuration
        print("📋 Step 1: Checking configuration...")
        let config = await configManager.colabConfiguration
        print("   Endpoint: \(config.endpointURL)")
        print("   Timeout: \(config.timeout)s")
        print("   Max Retries: \(config.maxRetries)")
        
        // Step 2: Test health check
        print("🏥 Step 2: Testing health check...")
        do {
            let health = try await colabClient.healthCheck()
            print("   ✅ Health check successful!")
            print("   Status: \(health.status)")
            print("   MagiV2 loaded: \(health.magiLoaded)")
            print("   XTTS-v2 loaded: \(health.xttsV2Loaded)")
            print("   Available speakers: \(health.availableSpeakers)")
        } catch {
            print("   ❌ Health check failed: \(error)")
            return
        }
        
        // Step 3: Test with sample image
        print("🖼️ Step 3: Testing with sample image...")
        let sampleImage = createSampleMangaPage()
        
        do {
            let jobId = try await colabClient.startAnalysis(pages: [sampleImage], characterBank: nil)
            print("   ✅ Analysis started successfully!")
            print("   Job ID: \(jobId)")
            
            // Step 4: Poll for completion
            print("⏳ Step 4: Waiting for analysis completion...")
            var attempts = 0
            let maxAttempts = 12 // 1 minute with 5-second intervals
            
            while attempts < maxAttempts {
                let status = try await colabClient.getAnalysisStatus(jobId: jobId)
                print("   Progress: \(Int(status.progress * 100))% - Status: \(status.status)")
                
                if status.status == "completed" {
                    print("   ✅ Analysis completed!")
                    
                    // Step 5: Get results
                    print("📊 Step 5: Retrieving results...")
                    let result = try await colabClient.getAnalysisResult(jobId: jobId)
                    print("   ✅ Results retrieved!")
                    print("   Pages analyzed: \(result.pages.count)")
                    print("   Transcript lines: \(result.transcript.count)")
                    
                    // Print sample results
                    if !result.transcript.isEmpty {
                        print("   Sample dialogue: \"\(result.transcript[0].text)\" - \(result.transcript[0].speaker)")
                    }
                    
                    break
                } else if status.status == "failed" {
                    print("   ❌ Analysis failed: \(status.error ?? "Unknown error")")
                    return
                }
                
                attempts += 1
                try await Task.sleep(nanoseconds: 5_000_000_000) // 5 seconds
            }
            
            if attempts >= maxAttempts {
                print("   ⏰ Analysis timed out")
            }
            
        } catch {
            print("   ❌ Analysis test failed: \(error)")
        }
        
        print("🎉 Connection test completed!")
    }
    
    private static func createSampleMangaPage() -> UIImage {
        // Create a simple test image with text
        let size = CGSize(width: 800, height: 1200)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        return renderer.image { context in
            // White background
            UIColor.white.setFill()
            context.fill(CGRect(origin: .zero, size: size))
            
            // Add some sample text (simulating manga dialogue)
            let text = "Hello! This is a test manga page."
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.boldSystemFont(ofSize: 24),
                .foregroundColor: UIColor.black
            ]
            
            let textRect = CGRect(x: 100, y: 200, width: 600, height: 100)
            text.draw(in: textRect, withAttributes: attributes)
            
            // Add a simple speech bubble outline
            let bubbleRect = CGRect(x: 80, y: 180, width: 640, height: 140)
            UIColor.black.setStroke()
            let bubblePath = UIBezierPath(roundedRect: bubbleRect, cornerRadius: 20)
            bubblePath.lineWidth = 3
            bubblePath.stroke()
        }
    }
}

// MARK: - SwiftUI Test View

import SwiftUI

struct ConnectionTestView: View {
    @State private var isRunning = false
    @State private var testOutput = "Ready to test connection..."
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Text("AI Analysis Connection Test")
                    .font(.title)
                    .padding()
                
                ScrollView {
                    Text(testOutput)
                        .font(.system(.body, design: .monospaced))
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color.gray.opacity(0.1))
                .cornerRadius(10)
                
                Button(action: runTest) {
                    HStack {
                        if isRunning {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isRunning ? "Testing..." : "Run Connection Test")
                    }
                    .padding()
                    .background(isRunning ? Color.gray : Color.blue)
                    .foregroundColor(.white)
                    .cornerRadius(10)
                }
                .disabled(isRunning)
            }
            .padding()
            .navigationTitle("Connection Test")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
    
    private func runTest() {
        isRunning = true
        testOutput = "Starting connection test...\n"
        
        Task {
            // Capture print output
            await AIAnalysisConnectionTest.testConnection()
            
            await MainActor.run {
                isRunning = false
                testOutput += "\nTest completed!"
            }
        }
    }
}

#Preview {
    ConnectionTestView()
}