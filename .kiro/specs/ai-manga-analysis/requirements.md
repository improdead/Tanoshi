# Requirements Document

## Introduction

This feature integrates AI-powered manga analysis capabilities into the Aidoku app by connecting to a Google Colab endpoint. The system will use MagiV2 for character recognition and OCR, and MeloTTS for text-to-speech dialogue simulation. Users will be able to analyze imported PDF manga pages to extract character dialogue, identify speakers, and generate audio narration of the manga content.

## Requirements

### Requirement 1

**User Story:** As a manga reader, I want the app to automatically connect to a pre-configured Google Colab endpoint, so that AI analysis works seamlessly without manual setup.

#### Acceptance Criteria

1. WHEN the app starts THEN the system SHALL automatically attempt to connect to the configured Google Colab endpoint
2. WHEN the endpoint is unavailable THEN the system SHALL retry in the background and disable AI features temporarily
3. WHEN the user provides a new Colab ngrok URL THEN the system SHALL automatically validate and switch to the new endpoint
4. WHEN the connection is established THEN the system SHALL automatically verify MagiV2 and MeloTTS availability and enable AI features

### Requirement 2

**User Story:** As a manga reader, I want the system to automatically analyze PDF manga when I open a chapter, so that character dialogue and speaker identification happens seamlessly.

#### Acceptance Criteria

1. WHEN the user opens a PDF manga chapter THEN the system SHALL automatically extract pages as images
2. WHEN pages are extracted THEN the system SHALL automatically send them to the Google Colab endpoint as base64-encoded images
3. IF the analysis fails THEN the system SHALL retry automatically and show a subtle notification
4. WHEN processing begins THEN the system SHALL show a non-intrusive progress indicator
5. WHEN analysis completes THEN the system SHALL automatically cache results and enable AI features for that chapter

### Requirement 3

**User Story:** As a manga reader, I want the system to identify characters and extract dialogue text, so that I can understand who is speaking in each panel.

#### Acceptance Criteria

1. WHEN manga pages are analyzed THEN the system SHALL extract OCR text from speech bubbles
2. WHEN character recognition runs THEN the system SHALL identify characters using the character bank
3. WHEN text-character associations are made THEN the system SHALL map dialogue to specific characters
4. IF character identification is uncertain THEN the system SHALL mark speakers as "unsure"
5. WHEN analysis is complete THEN the system SHALL generate a structured transcript with speaker names

### Requirement 4

**User Story:** As a manga reader, I want to maintain a character bank for each manga series, so that character recognition accuracy improves over time.

#### Acceptance Criteria

1. WHEN a new manga series is imported THEN the system SHALL create an empty character bank
2. WHEN users identify characters manually THEN the system SHALL add character images and names to the bank
3. WHEN the character bank is updated THEN the system SHALL use it for future analysis of the same series
4. IF multiple character images exist for one character THEN the system SHALL support multiple reference images
5. WHEN exporting/importing manga data THEN the system SHALL include character bank information

### Requirement 5

**User Story:** As a manga reader, I want to generate audio narration of manga dialogue, so that I can listen to the story being read aloud.

#### Acceptance Criteria

1. WHEN dialogue transcript is available THEN the system SHALL send text to MeloTTS for audio generation
2. WHEN generating audio THEN the system SHALL use different voices for different characters when possible
3. WHEN audio is generated THEN the system SHALL provide playback controls (play, pause, stop, seek)
4. IF audio generation fails THEN the system SHALL provide text-only fallback
5. WHEN audio playback is active THEN the system SHALL highlight the current dialogue text

### Requirement 6

**User Story:** As a manga reader, I want to view analysis results overlaid on manga pages, so that I can see which text was extracted and which characters were identified.

#### Acceptance Criteria

1. WHEN analysis results are received THEN the system SHALL display visual overlays on manga pages
2. WHEN displaying overlays THEN the system SHALL highlight detected text regions
3. WHEN showing character associations THEN the system SHALL indicate which character spoke each line
4. IF users tap on highlighted text THEN the system SHALL show detailed analysis information
5. WHEN viewing results THEN the system SHALL allow users to correct misidentified characters or text

### Requirement 7

**User Story:** As a manga reader, I want to export analysis results, so that I can save transcripts and share them with others.

#### Acceptance Criteria

1. WHEN analysis is complete THEN the system SHALL provide export options for transcripts
2. WHEN exporting THEN the system SHALL support multiple formats (JSON, plain text, structured formats)
3. WHEN sharing results THEN the system SHALL include character names, dialogue text, and page references
4. IF audio was generated THEN the system SHALL optionally include audio files in exports
5. WHEN exporting THEN the system SHALL respect user privacy settings and manga copyright considerations

### Requirement 8

**User Story:** As a manga reader, I want the AI analysis to work offline after initial processing, so that I can access results without internet connectivity.

#### Acceptance Criteria

1. WHEN analysis results are received THEN the system SHALL cache them locally
2. WHEN viewing previously analyzed manga THEN the system SHALL load results from local cache
3. IF cached audio exists THEN the system SHALL play it without internet connection
4. WHEN storage space is limited THEN the system SHALL provide options to manage cached analysis data
5. WHEN manga is deleted THEN the system SHALL clean up associated analysis cache