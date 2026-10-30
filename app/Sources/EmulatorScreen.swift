//
//  RetroPhone — EmulatorScreen.swift
//  Copyright (c) 2026 c12n Apps. MIT licensed.
//
import SwiftUI

struct EmulatorScreen: View {
    @EnvironmentObject var store: Store
    let machine: Machine
    @StateObject private var modelHolder = ModelHolder()
    @State private var showConsole = false

    final class ModelHolder: ObservableObject {
        var model: EmulatorModel?
    }

    var body: some View {
        VStack(spacing: 10) {
            if let model = modelHolder.model {
                EmulatorBody(model: model, showConsole: $showConsole)
            } else {
                ProgressView("Starting…")
            }
        }
        .navigationTitle(machine.name)
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if modelHolder.model == nil {
                let model = EmulatorModel(store: store, machine: machine)
                modelHolder.model = model
                model.start()
            }
        }
        .onDisappear { modelHolder.model?.stop() }
    }
}

private struct EmulatorBody: View {
    @ObservedObject var model: EmulatorModel
    @Binding var showConsole: Bool

    var body: some View {
        VStack(spacing: 10) {
            VStack(spacing: 2) {
                Text(model.status).font(.headline)
                if !model.detail.isEmpty {
                    Text(model.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let busy = model.busy {
                    HStack { ProgressView(); Text(busy).font(.caption) }
                }
                Text(model.diagnostics)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal)

            GeometryReader { geo in
                ZStack {
                    Color.black
                    if let frame = model.frame {
                        Image(uiImage: frame)
                            .resizable()
                            .interpolation(.none)
                            .aspectRatio(contentMode: .fit)
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            model.touch(
                                phase: value.translation == .zero ? "down" : "move",
                                at: value.location, in: geo.size)
                        }
                        .onEnded { value in
                            model.touch(phase: "up", at: value.location,
                                        in: geo.size)
                        })
            }
            .aspectRatio(320.0 / 480.0, contentMode: .fit)
            .padding(.horizontal)

            HStack(spacing: 24) {
                Button("Home") { tapHome() }
                    .buttonStyle(.bordered)
                Button("Power") { tapPower() }
                    .buttonStyle(.bordered)
                Button("Console") { showConsole = true }
                    .buttonStyle(.bordered)
            }
            .padding(.bottom, 8)
        }
        .sheet(isPresented: $showConsole) {
            NavigationStack {
                ScrollView {
                    Text(model.consoleText.isEmpty
                         ? "(no guest output yet)" : model.consoleText)
                        .font(.system(size: 10, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                }
                .navigationTitle("Guest console")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { showConsole = false }
                    }
                }
            }
        }
    }

    private func tapHome() {
        model.home(down: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            model.home(down: false)
        }
    }

    private func tapPower() {
        model.power(down: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            model.power(down: false)
        }
    }
}
