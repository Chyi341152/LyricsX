//
//  iTunesHelper.swift
//  LyricsX
//
//  Created by 邓翔 on 2017/2/6.
//  Copyright © 2017年 ddddxxx. All rights reserved.
//

import Foundation
import ScriptingBridge

class iTunesHelper: LyricsSourceDelegate {
    
    var iTunes: iTunesApplication!
    var lyricsHelper: LyricsSourceHelper
    
    var positionChangeTimer: Timer!
    
    var currentSongID: Int?
    var currentSongTitle: String?
    var currentArtist: String?
    var currentLyrics: LXLyrics? {
        didSet {
            appDelegate.currentOffset = currentLyrics?.offset ?? 0
        }
    }
    
    var currentLyricsLine: LXLyricsLine?
    var nextLyricsLine: LXLyricsLine?
    
    var fetchLrcQueue = OperationQueue()
    
    init() {
        iTunes = SBApplication(bundleIdentifier: "com.apple.iTunes")
        lyricsHelper = LyricsSourceHelper()
        lyricsHelper.delegate = self
        
        positionChangeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in self.handlePositionChange() }
        
        DistributedNotificationCenter.default().addObserver(forName: NSNotification.Name("com.apple.iTunes.playerInfo"), object: nil, queue: nil) { notification in self.handlePlayerInfoChange() }
        
        handlePlayerInfoChange()
    }
    
    func handlePlayerInfoChange () {
        let id = iTunes.currentTrack?.id?()
        if currentSongID != id {
            handleSongChange()
        }
        
        if let state = iTunes.playerState {
            switch state {
            case .iTunesEPlSPlaying:
                positionChangeTimer.fireDate = Date()
                print("playing")
            case .iTunesEPlSPaused, .iTunesEPlSStopped:
                positionChangeTimer.fireDate = .distantFuture
                print("Paused")
            default:
                break
            }
        }
    }
    
    func handleSongChange() {
        let track = iTunes.currentTrack
        currentSongID = track?.id?()
        currentSongTitle = track?.name as String?
        currentArtist = track?.artist as String?
        currentLyrics = nil
        
        print("song changed: \(currentSongTitle)")
        
        let info = ["lrc": "", "next": ""]
        NotificationCenter.default.post(name: .lyricsShouldDisplay, object: nil, userInfo: info)
        
        guard let title = currentSongTitle, let artist = currentArtist else {
            return
        }
        
        if let localLyrics = lyricsHelper.readLocalLyrics(title: title, artist: artist) {
            currentLyrics = localLyrics
            currentLyrics?.filtrate()
            currentLyrics?.smartFiltrate()
        } else {
            lyricsHelper.fetchLyrics(title: title, artist: artist)
        }
    }
    
    func handlePositionChange() {
        guard let lyrics = currentLyrics, let position = iTunes.playerPosition else {
            return
        }
        
        let lrc = lyrics[position]
        
        if currentLyricsLine == lrc.current {
            return
        }
        
        currentLyricsLine = lrc.current
        nextLyricsLine = lrc.next
        
        let info = [
            "lrc": currentLyricsLine?.sentence as Any,
            "next": nextLyricsLine?.sentence as Any
        ]
        NotificationCenter.default.post(name: .lyricsShouldDisplay, object: nil, userInfo: info)
    }
    
    // MARK: LyricsSourceDelegate
    
    func lyricsReceived(lyrics: LXLyrics) {
        guard lyrics.metadata[.searchTitle] == currentSongTitle, lyrics.metadata[.searchArtist] == currentArtist else {
            return
        }
        
        if currentLyrics == nil {   // TODO: replacement
            var lyrics = lyrics
            lyrics.filtrate()
            lyrics.smartFiltrate()
            currentLyrics = lyrics
            lyrics.saveToLocal()
        }
    }
    
}

extension LXLyrics {
    
    func saveToLocal() {
        let savingPath: String
        if UserDefaults.standard.integer(forKey: LyricsSavingPathPopUpIndex) == 0 {
            savingPath = LyricsSavingPathDefault
        } else {
            savingPath = UserDefaults.standard.string(forKey: LyricsCustomSavingPath)!
        }
        let fileManager = FileManager.default
        
        do {
            var isDir = ObjCBool(false)
            if fileManager.fileExists(atPath: savingPath, isDirectory: &isDir) {
                if !isDir.boolValue {
                    return
                }
            } else {
                try fileManager.createDirectory(atPath: savingPath, withIntermediateDirectories: true, attributes: nil)
            }
            
            let titleForSaving = metadata[.searchTitle]!.replacingOccurrences(of: "/", with: "&")
            let artistForSaving = metadata[.searchArtist]!.replacingOccurrences(of: "/", with: "&")
            let lrcFilePath = (savingPath as NSString).appendingPathComponent("\(titleForSaving) - \(artistForSaving).lrc")
            
            if fileManager.fileExists(atPath: lrcFilePath) {
                try fileManager.removeItem(atPath: lrcFilePath)
            }
            try description.write(toFile: lrcFilePath, atomically: false, encoding: String.Encoding.utf8)
        } catch let error as NSError{
            print(error)
            return
        }
    }
    
    mutating func filtrate() {
        let userDefaults = UserDefaults.standard
        guard let directFilter = userDefaults.array(forKey: LyricsDirectFilterKey) as? [String],
            let colonFilter = userDefaults.array(forKey: LyricsColonFilterKey) as? [String] else {
                return
        }
        let colons = [":", "：", "∶"]
        let directFilterPattern = directFilter.joined(separator: "|")
        let colonFilterPattern = colonFilter.joined(separator: "|")
        let colonsPattern = colons.joined(separator: "|")
        let pattern = "\(directFilterPattern)|((\(colonFilterPattern))(\(colonsPattern)))"
        if let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) {
            filtrate(using: regex)
        }
    }
    
}