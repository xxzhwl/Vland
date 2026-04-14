//
//  SparkleView.swift
//  DynamicIsland
//
//  Originally from boring.notch project
//  Modified and adapted for Vland (DynamicIsland)
//
//  Used for sparkle effects on the onboarding views
//

import SwiftUI

struct SparkleView: View {
    @State private var animating = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Radial gradient background
                RadialGradient(
                    gradient: Gradient(colors: [
                        Color.purple.opacity(0.3),
                        Color.blue.opacity(0.2),
                        Color.pink.opacity(0.1),
                        Color.clear
                    ]),
                    center: .center,
                    startRadius: 0,
                    endRadius: geometry.size.width * 0.6
                )

                // Animated sparkles
                ForEach(0..<15) { index in
                    SparkleParticleView(
                        size: geometry.size,
                        index: index,
                        animating: animating
                    )
                }
            }
        }
        .onAppear {
            withAnimation(
                .easeInOut(duration: Double.random(in: 2...4))
                .repeatForever(autoreverses: true)
            ) {
                animating = true
            }
        }
    }
}

struct SparkleParticleView: View {
    let size: CGSize
    let index: Int
    let animating: Bool

    @State private var offset: CGSize = .zero
    @State private var opacity: Double = 0

    var body: some View {
        Circle()
            .fill(Color.white.opacity(0.8))
            .frame(width: randomSize, height: randomSize)
            .offset(offset)
            .opacity(opacity)
            .onAppear {
                // Set random initial position
                let initialX = CGFloat.random(in: 0...size.width)
                let initialY = CGFloat.random(in: 0...size.height)
                offset = CGSize(width: initialX - size.width / 2, height: initialY - size.height / 2)

                // Animate opacity
                withAnimation(
                    .easeInOut(duration: Double.random(in: 1.5...3))
                    .repeatForever(autoreverses: true)
                    .delay(Double.random(in: 0...2))
                ) {
                    opacity = Double.random(in: 0.3...0.8)
                }

                // Animate offset (drift)
                let driftX = CGFloat.random(in: -20...20)
                let driftY = CGFloat.random(in: -30...10)
                withAnimation(
                    .easeInOut(duration: Double.random(in: 3...5))
                    .repeatForever(autoreverses: true)
                    .delay(Double.random(in: 0...1))
                ) {
                    offset = CGSize(
                        width: initialX - size.width / 2 + driftX,
                        height: initialY - size.height / 2 + driftY
                    )
                }
            }
    }

    var randomSize: CGFloat {
        CGFloat.random(in: 1.5...3.5)
    }
}

#Preview {
    SparkleView()
        .frame(width: 300, height: 400)
}