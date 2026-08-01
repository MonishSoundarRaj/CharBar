//
//  EmailHelper.swift
//  CharBar
//
//  Email helper for generating mailto links and opening default email client
//

import Foundation
import AppKit
import EventKit

/// Helper class for generating and opening email compose windows
class EmailHelper {
    static let shared = EmailHelper()
    
    private init() {}
    
    /// Generate a "Running Late" email for a meeting
    /// - Parameters:
    ///   - event: The calendar event
    ///   - minutes: How many minutes late (5, 10, 15, etc.)
    func sendRunningLateEmail(for event: EKEvent, minutes: Int) {
        let attendeeEmails = getAttendeeEmails(from: event)
        let organizer = organizerName(from: event)
        let subject = "Running Late: \(event.title ?? "Meeting")"
        let body = generateLateMessage(eventTitle: event.title ?? "the meeting", minutes: minutes, organizerName: organizer)
        openMailto(to: attendeeEmails, subject: subject, body: body)
    }
    
    /// Extract attendee emails from an event, including the organizer
    private func getAttendeeEmails(from event: EKEvent) -> [String] {
        var emails: [String] = []
        
        // Include organizer email first if available
        if let organizer = event.organizer, !organizer.isCurrentUser {
            let urlString = organizer.url.absoluteString
            if urlString.hasPrefix("mailto:") {
                emails.append(String(urlString.dropFirst(7)))
            }
        }
        
        if let attendees = event.attendees {
            for attendee in attendees {
                if attendee.isCurrentUser { continue }
                let urlString = attendee.url.absoluteString
                if urlString.hasPrefix("mailto:") {
                    let email = String(urlString.dropFirst(7))
                    if !emails.contains(email) {
                        emails.append(email)
                    }
                }
            }
        }
        
        return emails
    }
    
    /// Get the organizer name from an event
    func organizerName(from event: EKEvent) -> String? {
        return event.organizer?.name
    }
    
    /// Generate a friendly "running late" message
    private func generateLateMessage(eventTitle: String, minutes: Int, organizerName: String? = nil) -> String {
        let greeting: String
        if let name = organizerName {
            greeting = "Hi \(name) and everyone,"
        } else {
            greeting = ["Hi everyone,", "Hi all,", "Hey team,"].randomElement() ?? "Hi,"
        }
        
        let apologies = [
            "I'm running about \(minutes) minutes late to \(eventTitle).",
            "Apologies, I'll be approximately \(minutes) minutes late to \(eventTitle).",
            "Quick heads up — I'm running \(minutes) mins behind for \(eventTitle)."
        ]
        let apology = apologies.randomElement() ?? "I'm running \(minutes) minutes late."
        
        let closings = [
            "I'll join as soon as I can!",
            "Be there shortly!",
            "See you soon!"
        ]
        let closing = closings.randomElement() ?? "See you soon!"
        
        return """
        \(greeting)
        
        \(apology)
        
        \(closing)
        """
    }
    
    /// Open the system's default email client with pre-filled content
    /// - Parameters:
    ///   - to: Array of recipient email addresses
    ///   - subject: Email subject line
    ///   - body: Email body text
    func openMailto(to recipients: [String], subject: String, body: String) {
        // Build mailto URL
        var components = URLComponents()
        components.scheme = "mailto"
        components.path = recipients.joined(separator: ",")
        
        var queryItems: [URLQueryItem] = []
        queryItems.append(URLQueryItem(name: "subject", value: subject))
        queryItems.append(URLQueryItem(name: "body", value: body))
        components.queryItems = queryItems
        
        // Open the URL - this works with Mail, Gmail (if configured), Outlook, etc.
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }
    
    /// Open an event in the Calendar app
    func showInCalendar(event: EKEvent) {
        // Open Calendar app using bundle identifier (more reliable than URL scheme)
        if let calendarURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.iCal") {
            NSWorkspace.shared.open(calendarURL)
        } else {
            // Fallback: try to open by name
            NSWorkspace.shared.launchApplication("Calendar")
        }
    }
    
    /// Send a custom email
    func sendEmail(to recipients: [String], subject: String, body: String) {
        openMailto(to: recipients, subject: subject, body: body)
    }
}

