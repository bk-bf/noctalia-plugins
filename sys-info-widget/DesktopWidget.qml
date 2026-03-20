import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Modules.DesktopWidgets
import qs.Widgets 

DraggableDesktopWidget {
    id: root
    property var pluginApi: null

    readonly property real _width: Math.round(300 * widgetScale)
    readonly property real _height: Math.round(165 * widgetScale)
    
    implicitWidth:  _width
    implicitHeight: _height

    // --- Data Variables ---
    // We use a fallback string in case the translation file isn't loaded yet
    property string distroVal: "..."
    property string kernelVal: "..."
    property string uptimeVal: "..."

    // --- Data Fetching ---

    // Distribution Fetcher
    Process {
        id: distroProc
        command: ["sh", "-c", "grep '^NAME=' /etc/os-release | cut -d'=' -f2 | tr -d '\"'"]
        running: true
        stdout: StdioCollector { 
            onStreamFinished: { if (text.trim() !== "") root.distroVal = text.trim(); } 
        }
    }

    // Kernel Fetcher
    Process {
        id: kernelProc
        command: ["uname", "-r"]
        running: true
        stdout: StdioCollector { 
            onStreamFinished: { if (text.trim() !== "") root.kernelVal = text.trim(); } 
        }
    }

    // Uptime Fetcher
    Process {
        id: uptimeProc
        command: ["sh", "-c", "awk '{d=int($1/86400); h=int(($1%86400)/3600); m=int(($1%3600)/60); if(d>0) printf \"%dd \", d; printf \"%dh %dm\", h, m}' /proc/uptime"]
        running: true
        stdout: StdioCollector {
            onStreamFinished: { if (text.trim() !== "") root.uptimeVal = text.trim(); }
        }
    }

    Timer { 
        interval: 60000; 
        running: true; 
        repeat: true; 
        onTriggered: uptimeProc.running = true 
    }

    // --- UI Layout ---
Rectangle {
    anchors.fill: parent
    // If Color.mSurface is undefined, it defaults to a hex string
    color: (Color && Color.mSurface) ? Color.mSurface : "#242424" 
    opacity: 0.85
    radius: Style.radiusM ?? 8 // Fallback for Style too
    border.color: (Color && Color.mOutlineVariant) ? Color.mOutlineVariant : "#444444"
    border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Style.marginL
            spacing: Style.marginS

            GridLayout {
                columns: 2
                Layout.fillWidth: true
                rowSpacing: Style.marginS

                // Row 1: Distribution
                NText { 
                    text: pluginApi?.tr("widget.distribution") ?? "Distribution"
                    color: Color.mOnSurfaceVariant
                    font.pointSize: 11 
                }
                NText { 
                    text: root.distroVal
                    color: Color.mOnSurface
                    font.bold: true
                    font.pointSize: 11
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight 
                }

                // Row 2: Kernel
                NText { 
                    text: pluginApi?.tr("widget.kernel") ?? "Kernel"
                    color: Color.mOnSurfaceVariant
                    font.pointSize: 11
                }
                NText { 
                    text: root.kernelVal
                    color: Color.mOnSurface
                    font.bold: true
                    font.pointSize: 11
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideNone 
                    wrapMode: Text.NoWrap
                }

                // Row 3: Uptime
                NText { 
                    text: pluginApi?.tr("widget.uptime") ?? "Uptime"
                    color: Color.mOnSurfaceVariant
                    font.pointSize: 11
                }
                NText { 
                    text: root.uptimeVal
                    color: Color.mOnSurface
                    font.bold: true
                    font.pointSize: 11
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignRight 
                }
            }
        }
    }
}
