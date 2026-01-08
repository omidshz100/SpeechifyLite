//
//  ReaderViewModel.swift
//  SpeechifyLite
//
//  Created by Omid Shojaeian Zanjani on 07/01/26.
//
import Foundation
import Combine

@MainActor
final class ReaderViewModel: ObservableObject {
    @Published var text: String = "سلام! اینجا متن را وارد کن و Speak را بزن."
}
