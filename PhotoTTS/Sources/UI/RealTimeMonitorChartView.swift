//
//  RealTimeMonitorChartView.swift
//  PhotoTTS
//
//  实时监控时序图表组件
//

import SwiftUI

// MARK: - 时序图表视图
struct RealTimeMonitorChartView: View {
    private let data: MetricData
    private let color: Color
    private let chartHeight: CGFloat = 120
    
    init(data: MetricData, color: Color = .gray) {
        self.data = data
        self.color = color
    }
    
    var body: some View {
        // 图表区域
        ZStack(alignment: .bottomLeading) {
            // 背景
            Rectangle()
                .fill(Color(.systemBackground))
                .frame(height: chartHeight)
            
            // 网格线和曲线
            Canvas { context, size in
                // 绘制水平网格线
                let gridLines = 4
                for i in 0...gridLines {
                    let y = size.height * CGFloat(i) / CGFloat(gridLines)
                    let linePath = Path { p in
                        p.move(to: CGPoint(x: 0, y: y))
                        p.addLine(to: CGPoint(x: size.width, y: y))
                    }
                    context.stroke(linePath, with: .color(.gray.opacity(0.3)), lineWidth: 1)
                }
                
                // 绘制曲线
                if data.points.count > 1 {
                    drawCurve(context: context, size: size, points: data.points, maxValue: getMaxValue(), color: color)
                }
            }
            .frame(height: chartHeight)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(.systemGroupedBackground))
                .stroke(Color(.systemGray5), lineWidth: 1)
        )
    }
    
    // MARK: - 获取最大值（用于 Y 轴缩放）
    private func getMaxValue() -> Double {
        guard !data.points.isEmpty else { return 100 }
        
        let maxFromPoints = data.points.map { $0.value }.max() ?? 0
        let maxFromCurrent = data.currentValue
        let maxFromPeak = data.peakValue
        
        let maxValue = max(maxFromPoints, maxFromCurrent, maxFromPeak)
        
        // 根据指标类型调整最大值
        switch data.type {
        case .cpu:
            return max(100, maxValue * 1.2) // CPU 最大 100%，留 20% 余量
        case .memory:
            return max(1024, maxValue * 1.2) // 内存至少 1GB
        case .disk, .network:
            return max(10, maxValue * 1.2) // 至少 10 MB/s
        }
    }
    
    // MARK: - 绘制曲线
    private func drawCurve(context: GraphicsContext, size: CGSize, points: [MetricPoint], maxValue: Double, color: Color) {
        guard points.count > 1 else { return }
        
        let pathWidth = size.width
        let pathHeight = size.height
        
        // 计算 X 轴步长
        let stepX = pathWidth / CGFloat(points.count - 1)
        
        // 构建路径
        var path = Path()
        
        for (index, point) in points.enumerated() {
            let x = CGFloat(index) * stepX
            let normalizedY = CGFloat(point.value / maxValue)
            let y = pathHeight - normalizedY * pathHeight
            
            if index == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                // 使用贝塞尔曲线使曲线平滑
                let prevPoint = points[index - 1]
                let prevX = CGFloat(index - 1) * stepX
                let prevNormalizedY = CGFloat(prevPoint.value / maxValue)
                let prevY = pathHeight - prevNormalizedY * pathHeight
                
                let controlX1 = prevX + (x - prevX) / 2
                let controlY1 = prevY
                let controlX2 = prevX + (x - prevX) / 2
                let controlY2 = y
                
                path.addCurve(
                    to: CGPoint(x: x, y: y),
                    control1: CGPoint(x: controlX1, y: controlY1),
                    control2: CGPoint(x: controlX2, y: controlY2)
                )
            }
        }
        
        // 绘制曲线（使用传入的颜色）
        context.stroke(path, with: .color(color), lineWidth: 2)
        
        // 绘制填充区域
        if points.count > 1 {
            var fillPath = Path(path.cgPath)
            fillPath.addLine(to: CGPoint(x: pathWidth, y: pathHeight))
            fillPath.addLine(to: CGPoint(x: 0, y: pathHeight))
            fillPath.closeSubpath()
            
            context.fill(fillPath, with: .color(color.opacity(0.1)))
        }
    }
}

// MARK: - 预览
#Preview {
    RealTimeMonitorChartView(data: MetricData(
        type: .cpu,
        points: [
            MetricPoint(timestamp: Date(), value: 20),
            MetricPoint(timestamp: Date().addingTimeInterval(1), value: 30),
            MetricPoint(timestamp: Date().addingTimeInterval(2), value: 45),
            MetricPoint(timestamp: Date().addingTimeInterval(3), value: 35),
            MetricPoint(timestamp: Date().addingTimeInterval(4), value: 50)
        ],
        currentValue: 50,
        peakValue: 78
    ))
}