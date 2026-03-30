import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons
import qs.Services.UI
import qs.Widgets

Item {
  id: root

  property var pluginApi: null
  readonly property var geometryPlaceholder: panelContainer
  property real contentPreferredWidth: 350 * Style.uiScaleRatio
  property real contentPreferredHeight: 500 * Style.uiScaleRatio
  readonly property bool allowAttach: true
  anchors.fill: parent
  property ListModel filteredTodosModel: ListModel {}
  property ListModel filteredCompletedModel: ListModel {}
  property bool showCompleted: false
  property var rawTodos: []
  property int currentPageId: 0
  property bool showEmptyState: false
  property bool detailsEditMode: false

  // Reference to Main.qml instance for centralized data management
  readonly property var mainInstance: pluginApi?.mainInstance

  // Define a function to schedule reloading of todos
  function scheduleReload() {
    Qt.callLater(loadTodos);
  }

  // Bind rawTodos, showCompleted, and currentPageId to plugin settings
  Binding {
    target: root
    property: "rawTodos"
    value: pluginApi?.pluginSettings?.todos || []
  }

  // showCompleted controls whether the completed section is expanded.
  // Initialised from settings once; toggled locally and written back.
  Binding {
    target: root
    property: "showCompleted"
    value: pluginApi?.pluginSettings?.showCompleted !== undefined ? pluginApi.pluginSettings.showCompleted : false
    restoreMode: Binding.RestoreNone
  }

  Binding {
    target: root
    property: "currentPageId"
    value: pluginApi?.pluginSettings?.current_page_id || 0
  }

  Component.onCompleted: {
    if (pluginApi) {
      Logger.i("Todo", "Panel initialized");
    }
  }

  onPluginApiChanged: {
    if (pluginApi) {
      loadTodos();
    }
  }

  // Listen for changes that affect the todo list display
  onRawTodosChanged: scheduleReload()
  onCurrentPageIdChanged: scheduleReload()

  Rectangle {
    id: panelContainer
    anchors.fill: parent
    color: "transparent"

    ColumnLayout {
      anchors {
        fill: parent
        margins: Style.marginM
      }
      spacing: Style.marginL

      Rectangle {
        Layout.fillWidth: true
        Layout.fillHeight: true
        color: Color.mSurfaceVariant
        radius: Style.radiusL

        ColumnLayout {
          anchors.fill: parent
          anchors.margins: Style.marginM
          spacing: Style.marginM

          RowLayout {
            spacing: Style.marginM

            NIcon {
              icon: "clipboard-check"
              pointSize: Style.fontSizeXL
            }

            NText {
              text: pluginApi?.tr("panel.header.title")
              font.pointSize: Style.fontSizeL
              font.weight: Font.Medium
              color: Color.mOnSurface
            }

            Item {
              Layout.fillWidth: true
            }

            NIconButton {
              icon: "download"
              baseSize: Style.baseWidgetSize
              customRadius: Style.iRadiusS
              ToolTip.visible: hovered
              ToolTip.text: pluginApi?.tr("panel.header.export_button")
              ToolTip.delay: 800
              onClicked: {
                if (mainInstance)
                  mainInstance.doExportTodos();
              }
            }

            NIconButton {
              icon: mainInstance?.googleSyncStatus === "syncing" ? "arrows-rotate" : "cloud"
              baseSize: Style.baseWidgetSize
              customRadius: Style.iRadiusS
              enabled: mainInstance?.googleSyncStatus !== "syncing"
                    && mainInstance?.googleSyncStatus !== "authenticating"
              ToolTip.visible: hovered
              ToolTip.text: mainInstance?.googleSyncStatus === "syncing"
                  ? pluginApi?.tr("google_sync.syncing")
                  : pluginApi?.tr("panel.header.sync_list_button")
              ToolTip.delay: 800
              onClicked: {
                if (!mainInstance) return;
                if (!mainInstance.googleSignedInEmail) {
                  ToastService.showNotice(pluginApi.tr("google_sync.error_not_signed_in_panel"));
                } else {
                  mainInstance.doGoogleSync(root.currentPageId);
                }
              }
            }

            NIconButton {
              icon: "cloud-arrow-up"
              baseSize: Style.baseWidgetSize
              customRadius: Style.iRadiusS
              visible: (mainInstance?.googleSignedInEmail || "") !== ""
              enabled: mainInstance?.googleSyncStatus !== "syncing"
                    && mainInstance?.googleSyncStatus !== "authenticating"
              ToolTip.visible: hovered
              ToolTip.text: pluginApi?.tr("panel.header.sync_all_button")
              ToolTip.delay: 800
              onClicked: {
                if (!mainInstance) return;
                mainInstance.doGoogleSync();
              }
            }

            NIconButton {
              icon: "trash"
              baseSize: Style.baseWidgetSize
              customRadius: Style.iRadiusS
              enabled: (pluginApi?.pluginSettings?.completedCount ?? 0) > 0
              ToolTip.visible: hovered
              ToolTip.text: pluginApi?.tr("panel.header.clear_completed_button")
              ToolTip.delay: 800
              onClicked: {
                clearCompletedTodos();
              }
            }
          }

          // Page selector using tab components
          NTabBar {
            id: tabBar
            Layout.fillWidth: true
            Layout.topMargin: Style.marginS
            distributeEvenly: true
            currentIndex: currentPageIndex

            // Track current page index
            property int currentPageIndex: {
              var pages = pluginApi?.pluginSettings?.pages || [];
              var currentId = pluginApi?.pluginSettings?.current_page_id || 0;
              for (var i = 0; i < pages.length; i++) {
                if (pages[i].id === currentId) {
                  return i;
                }
              }
              return 0;
            }

            // Dynamically create tabs based on pages
            Repeater {
              model: pluginApi?.pluginSettings?.pages || []

              delegate: NTabButton {
                id: tabButton
                text: modelData.name
                tabIndex: index
                checked: index === tabBar.currentIndex

                Component.onCompleted: {
                  topLeftRadius = Style.iRadiusM;
                  bottomLeftRadius = Style.iRadiusM;
                  topRightRadius = Style.iRadiusM;
                  bottomRightRadius = Style.iRadiusM;
                }

                onClicked: {
                  pluginApi.pluginSettings.current_page_id = modelData.id;
                  pluginApi.saveSettings();
                }
              }
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true

            RowLayout {
              spacing: Style.marginS
              Layout.bottomMargin: Style.marginM

              NTextInput {
                id: newTodoInput
                placeholderText: pluginApi?.tr("panel.add_todo.placeholder")
                Layout.fillWidth: true
                Keys.onReturnPressed: addTodo()
              }

              // Priority selector using a simplified approach
              Item {
                Layout.preferredWidth: 120
                Layout.preferredHeight: Style.baseWidgetSize * 0.95

                Rectangle {
                  anchors.fill: parent
                  color: "transparent"
                  border.color: Color.mOutline
                  border.width: 1
                  radius: Style.iRadiusS

                  Row {
                    anchors.fill: parent
                    spacing: 1

                    Rectangle {
                      id: highPriorityBtn
                      width: (parent.width - 2) / 3
                      height: parent.height
                      color: priorityGroup.currentPriority === "high" ? getPriorityColor("high") : "transparent"
                      radius: Style.iRadiusS

                      NText {
                        anchors.centerIn: parent
                        text: "H"
                        color: priorityGroup.currentPriority === "high" ? Color.mOnPrimary : getPriorityColor("high")
                        font.pointSize: Style.fontSizeS
                      }

                      MouseArea {
                        anchors.fill: parent
                        onClicked: priorityGroup.currentPriority = "high"
                      }
                    }

                    Rectangle {
                      id: mediumPriorityBtn
                      width: (parent.width - 2) / 3
                      height: parent.height
                      color: priorityGroup.currentPriority === "medium" ? getPriorityColor("medium") : "transparent"
                      radius: Style.iRadiusS

                      NText {
                        anchors.centerIn: parent
                        text: "M"
                        color: priorityGroup.currentPriority === "medium" ? Color.mOnPrimary : getPriorityColor("medium")
                        font.pointSize: Style.fontSizeS
                      }

                      MouseArea {
                        anchors.fill: parent
                        onClicked: priorityGroup.currentPriority = "medium"
                      }
                    }

                    Rectangle {
                      id: lowPriorityBtn
                      width: parent.width - (highPriorityBtn.width + mediumPriorityBtn.width + 2)
                      height: parent.height
                      color: priorityGroup.currentPriority === "low" ? getPriorityColor("low") : "transparent"
                      radius: Style.iRadiusS

                      NText {
                        anchors.centerIn: parent
                        text: "L"
                        color: priorityGroup.currentPriority === "low" ? Color.mOnPrimary : getPriorityColor("low")
                        font.pointSize: Style.fontSizeS
                      }

                      MouseArea {
                        anchors.fill: parent
                        onClicked: priorityGroup.currentPriority = "low"
                      }
                    }
                  }
                }
              }

              // Define the priority group as a separate object
              QtObject {
                id: priorityGroup
                property string currentPriority: "medium"
              }

              NIconButton {
                icon: "plus"
                baseSize: Style.baseWidgetSize * 1.2
                customRadius: Style.iRadiusS
                onClicked: {
                  addTodo();
                  priorityGroup.currentPriority = "medium"; // Reset to default after adding
                }
              }
            }

            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true

            ListView {
              id: todoListView
              anchors.fill: parent
              clip: true
              model: root.filteredTodosModel
              spacing: Style.marginS
              boundsBehavior: Flickable.StopAtBounds
              flickableDirection: Flickable.VerticalFlick

              delegate: Item {
                id: delegateItem
                width: ListView.view.width
                property bool hasMeta: (modelData.dueDate !== "") || (modelData.subtaskCount > 0)
                property bool subtasksExpanded: false
                property int subtaskRowH: Math.round(Style.baseWidgetSize * 0.85) + 2
                property var subtaskItems: {
                  if (!subtasksExpanded) return [];
                  var subs = [];
                  var pid = String(modelData.id);
                  var todos = root.rawTodos || [];
                  for (var i = 0; i < todos.length; i++) {
                    if (String(todos[i].parentId) === pid) subs.push(todos[i]);
                  }
                  return subs;
                }
                height: Style.baseWidgetSize + (hasMeta ? 18 : 0) + Style.marginS
                        + (subtasksExpanded && modelData.subtaskCount > 0
                           ? modelData.subtaskCount * subtaskRowH + Style.marginS : 0)

                required property int index
                required property var modelData

                // Properties for drag functionality
                property bool dragging: false
                property int dragStartY: 0
                property int dragStartIndex: -1
                property int dragTargetIndex: -1
                property int itemSpacing: Style.marginS

                // Properties for edit functionality
                property bool editing: false
                property string originalText: ""

                // Methods for edit functionality
                function startEdit() {
                  editing = true;
                  originalText = modelData.text;
                }

                function saveEdit() {
                  if (mainInstance && todoTextEdit.text.trim() !== "") {
                    updateTodo(modelData.id, {
                                 text: todoTextEdit.text.trim()
                               });
                  }
                  editing = false;
                }

                function cancelEdit() {
                  editing = false;
                  // Restore the original text when cancelling
                  if (todoTextEdit) {
                    todoTextEdit.text = originalText;
                  }
                }

                // Watch for editing property changes to handle focus
                onEditingChanged: {
                  if (editing) {
                    // Use a timer to delay the focus operation
                    var timer = Qt.createQmlObject("
                            import QtQuick 2.0;
                            Timer {
                                interval: 50;
                                running: true;
                                onTriggered: {
                                    if (todoTextEdit && todoTextEdit.input) {
                                        todoTextEdit.input.forceActiveFocus();
                                    }
                                }
                            }", delegateItem);
                  }
                }

                Behavior on height {
                  NumberAnimation {
                    duration: Style.animationNormal
                    easing.type: Easing.OutQuad
                  }
                }

                // The actual todo item rectangle
                Rectangle {
                  anchors.fill: parent
                  color: Color.mSurface
                  radius: Style.radiusS

                  // Mouse area for clicking the entire item to view details
                  MouseArea {
                    anchors.fill: parent
                    onClicked: {
                      if (!delegateItem.editing) {
                        root.openTodoDetails(modelData);
                      }
                    }
                  }

                  RowLayout {
                    id: mainTaskRow
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.topMargin: Math.round(Style.marginS / 2)
                    anchors.leftMargin: Style.marginM
                    anchors.rightMargin: Style.marginM
                    spacing: Style.marginS
                    height: Style.baseWidgetSize + (delegateItem.hasMeta ? 18 : 0)

                    // Drag handle
                    Item {
                      id: dragHandle

                      Layout.preferredWidth: Style.baseWidgetSize * 0.5
                      Layout.preferredHeight: Style.baseWidgetSize * 0.8

                      NIcon {
                        id: dragHandleIcon
                        anchors.centerIn: parent
                        icon: "grip-vertical"
                        pointSize: Style.fontSizeM
                        color: Color.mOnSurfaceVariant
                        opacity: 0.5

                        states: [
                          State {
                            name: "hovered"
                            when: dragHandleMouseArea.containsMouse
                            PropertyChanges {
                              target: dragHandleIcon
                              opacity: 1.0
                              color: Color.mOnSurface
                            }
                          }
                        ]

                        transitions: [
                          Transition {
                            from: "*"
                            to: "hovered"
                            NumberAnimation {
                              properties: "opacity"
                              duration: 150
                            }
                          },
                          Transition {
                            from: "hovered"
                            to: "*"
                            NumberAnimation {
                              properties: "opacity"
                              duration: 150
                            }
                          }
                        ]
                      }

                      MouseArea {
                        id: dragHandleMouseArea

                        anchors.fill: parent
                        cursorShape: Qt.SizeVerCursor
                        hoverEnabled: true
                        preventStealing: false
                        z: 1000

                        onPressed: mouse => {
                                     delegateItem.dragStartIndex = delegateItem.index;
                                     delegateItem.dragTargetIndex = delegateItem.index;
                                     delegateItem.dragStartY = delegateItem.y;
                                     delegateItem.dragging = true;
                                     delegateItem.z = 999;

                                     // Signal that interaction started (prevents panel close)
                                     preventStealing = true;
                                   }

                        onPositionChanged: mouse => {
                                             if (delegateItem.dragging) {
                                               var dy = mouse.y - dragHandle.height / 2;
                                               var newY = delegateItem.y + dy;

                                               // Constrain within bounds
                                               newY = Math.max(0, Math.min(newY, todoListView.contentHeight - delegateItem.height));
                                               delegateItem.y = newY;

                                               // Determine target index by finding which item the dragged center overlaps
                                               var centerY = newY + delegateItem.height / 2;
                                               var bestIdx = delegateItem.dragStartIndex;
                                               for (var k = 0; k < todoListView.count; k++) {
                                                 var itm = todoListView.itemAtIndex(k);
                                                 if (itm && !itm.dragging) {
                                                   if (centerY >= itm.y && centerY < itm.y + itm.height) {
                                                     bestIdx = k;
                                                     break;
                                                   }
                                                 }
                                               }
                                               delegateItem.dragTargetIndex = bestIdx;
                                             }
                                           }

                        onReleased: {
                          // Apply the model change now that drag is complete
                          if (delegateItem.dragStartIndex !== -1 && delegateItem.dragTargetIndex !== -1 && delegateItem.dragStartIndex !== delegateItem.dragTargetIndex) {
                            moveTodoItem(delegateItem.dragStartIndex, delegateItem.dragTargetIndex);
                          }

                          delegateItem.dragging = false;
                          delegateItem.dragStartIndex = -1;
                          delegateItem.dragTargetIndex = -1;
                          delegateItem.z = 0;

                          // Reset interaction prevention
                          preventStealing = false;
                        }

                        onCanceled: {
                          // Handle cancel (e.g., ESC key pressed during drag)
                          delegateItem.dragging = false;
                          delegateItem.dragStartIndex = -1;
                          delegateItem.dragTargetIndex = -1;
                          delegateItem.z = 0;

                          // Reset interaction prevention
                          preventStealing = false;
                        }
                      }
                    }

                    // Priority indicator - a colored vertical line
                    Rectangle {
                      id: priorityIndicator
                      Layout.preferredWidth: 4  // Width of the priority line
                      Layout.preferredHeight: parent.height - Style.marginS
                      Layout.alignment: Qt.AlignVCenter  // Align vertically centered
                      radius: 2

                      // Determine color based on priority using helper function
                      color: {
                        if (pluginApi) {
                          return getPriorityColor(modelData.priority || "medium");
                        } else {
                          // Fallback to default colors if pluginApi is not ready
                          var priority = modelData.priority || "medium";
                          if (priority === "high") {
                            return Color.mError;
                          } else if (priority === "low") {
                            return Color.mOnSurfaceVariant;
                          } else {
                            return Color.mPrimary;
                          }
                        }
                      }
                    }

                    // Checkbox
                    Item {
                      Layout.preferredWidth: Style.baseWidgetSize * 0.7
                      Layout.preferredHeight: Style.baseWidgetSize * 0.7

                      Rectangle {
                        id: box

                        anchors.fill: parent
                        radius: Style.iRadiusXS
                        color: modelData.completed ? Color.mPrimary : Color.mSurface
                        border.color: Color.mOutline
                        border.width: Style.borderS

                        Behavior on color {
                          ColorAnimation {
                            duration: Style.animationFast
                          }
                        }

                        NIcon {
                          visible: modelData.completed
                          anchors.centerIn: parent
                          anchors.horizontalCenterOffset: -1
                          icon: "check"
                          color: Color.mOnPrimary
                          pointSize: Math.max(Style.fontSizeXS, Style.baseWidgetSize * 0.7 * 0.5)
                        }

                        MouseArea {
                          anchors.fill: parent
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            toggleTodo(modelData.id, modelData.completed);
                          }
                        }
                      }
                    }

                    // Text container (using Layout to fit in the RowLayout)
                    Item {
                      Layout.fillWidth: true
                      Layout.preferredHeight: parent.height

                      // Normal text display
                      NText {
                        id: todoTextDisplay
                        visible: !delegateItem.editing
                        text: modelData.text
                        color: modelData.completed ? Color.mOnSurfaceVariant : Color.mOnSurface
                        font.strikeout: modelData.completed
                        verticalAlignment: delegateItem.hasMeta ? Text.AlignTop : Text.AlignVCenter
                        topPadding: delegateItem.hasMeta ? Style.marginS : 0
                        elide: Text.ElideRight
                        anchors.left: parent.left
                        anchors.right: metaChips.visible ? metaChips.left : parent.right
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        anchors.leftMargin: Style.marginS
                        anchors.rightMargin: Style.marginXS
                      }

                      // Meta chips: due date + subtask count
                      Row {
                        id: metaChips
                        visible: delegateItem.hasMeta && !delegateItem.editing
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 4
                        anchors.rightMargin: Style.marginXS
                        spacing: 4

                        Rectangle {
                          visible: modelData.dueDate !== ""
                          width: dueDateLabel.implicitWidth + 8
                          height: 16
                          radius: 3
                          color: isDueOverdue(modelData.dueDate) ? Color.mError
                               : isDueToday(modelData.dueDate)   ? Qt.darker(Color.mPrimary, 1.3)
                               : Color.mSurfaceVariant

                          NText {
                            id: dueDateLabel
                            anchors.centerIn: parent
                            text: formatDueDate(modelData.dueDate)
                            font.pointSize: Style.fontSizeXS
                            color: isDueOverdue(modelData.dueDate) || isDueToday(modelData.dueDate)
                                   ? Color.mOnPrimary : Color.mOnSurfaceVariant
                          }
                        }

                        Rectangle {
                          id: subtaskBadge
                          visible: modelData.subtaskCount > 0
                          width: subtaskLabel.implicitWidth + 8
                          height: 16
                          radius: 3
                          color: delegateItem.subtasksExpanded ? Color.mPrimary : Color.mSurfaceVariant

                          NText {
                            id: subtaskLabel
                            anchors.centerIn: parent
                            text: (delegateItem.subtasksExpanded ? "\u25bc" : "\u25b6") + " " + modelData.subtaskCount
                            font.pointSize: Style.fontSizeXS
                            color: delegateItem.subtasksExpanded ? Color.mOnPrimary : Color.mOnSurfaceVariant
                          }

                          MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(mouse) {
                              delegateItem.subtasksExpanded = !delegateItem.subtasksExpanded;
                              mouse.accepted = true;
                            }
                          }
                        }
                      }

                      // Edit text field - Using TextField directly to have more control
                      Item {
                        id: todoTextEditContainer
                        visible: delegateItem.editing
                        anchors.fill: parent
                        anchors.leftMargin: Style.marginS
                        anchors.rightMargin: Style.baseWidgetSize * 0.4
                        height: parent.height * 0.8
                        anchors.verticalCenter: parent.verticalCenter

                        TextField {
                          id: todoTextEdit
                          anchors.fill: parent
                          anchors.rightMargin: Style.baseWidgetSize * 0.8
                          text: modelData.text

                          verticalAlignment: TextInput.AlignVCenter

                          echoMode: TextInput.Normal
                          color: Color.mOnSurface
                          placeholderTextColor: Qt.alpha(Color.mOnSurfaceVariant, 0.6)

                          selectByMouse: true

                          topPadding: 0
                          bottomPadding: 0
                          leftPadding: Style.marginS
                          rightPadding: Style.baseWidgetSize * 0.6

                          font.family: Settings.data.ui.fontDefault
                          font.pointSize: Style.fontSizeS * Style.uiScaleRatio
                          font.weight: Style.fontWeightRegular

                          // Remove the frame/background to eliminate border
                          background: null

                          Keys.onReturnPressed: {
                            delegateItem.saveEdit();
                          }

                          Keys.onEscapePressed: {
                            delegateItem.cancelEdit();
                          }

                          // Set focus when visible
                          onVisibleChanged: {
                            if (visible) {
                              Qt.callLater(function () {
                                todoTextEdit.forceActiveFocus();
                              });
                            }
                          }
                        }

                        // Clear button
                        Item {
                          implicitWidth: Style.baseWidgetSize * 1.1
                          implicitHeight: Style.baseWidgetSize * 1.1

                          anchors.right: parent.right
                          anchors.verticalCenter: parent.verticalCenter
                          anchors.rightMargin: Style.marginM

                          visible: todoTextEdit.text.length > 0

                          NIcon {
                            id: clearButtonIcon
                            anchors.centerIn: parent
                            icon: "backspace"
                            pointSize: Style.fontSizeL
                            color: Color.mOnSurfaceVariant
                            opacity: 0.5

                            MouseArea {
                              id: clearMouseArea
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: {
                                todoTextEdit.clear();
                                todoTextEdit.forceActiveFocus();
                              }

                              states: [
                                State {
                                  name: "hovered"
                                  when: clearMouseArea.containsMouse
                                  PropertyChanges {
                                    target: clearButtonIcon
                                    opacity: 1.0
                                    color: Color.mError
                                  }
                                }
                              ]

                              transitions: [
                                Transition {
                                  from: "*"
                                  to: "hovered"
                                  NumberAnimation {
                                    properties: "opacity"
                                    duration: 150
                                  }
                                },
                                Transition {
                                  from: "hovered"
                                  to: "*"
                                  NumberAnimation {
                                    properties: "opacity"
                                    duration: 150
                                  }
                                }
                              ]
                            }
                          }
                        }
                      }
                    }

                    // Edit button (only show when not editing)
                    Item {
                      Layout.preferredWidth: Style.baseWidgetSize * 0.8
                      Layout.preferredHeight: parent.height
                      visible: !delegateItem.editing

                      Item {
                        id: editButtonContainer
                        anchors.centerIn: parent

                        implicitWidth: Style.baseWidgetSize * 0.8
                        implicitHeight: Style.baseWidgetSize * 0.8

                        NIcon {
                          id: editButtonIcon
                          anchors.centerIn: parent
                          icon: "pencil"
                          pointSize: Style.fontSizeM
                          color: Color.mOnSurfaceVariant
                          opacity: 0.5

                          MouseArea {
                            id: editMouseArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                              delegateItem.startEdit();
                            }
                          }

                          ToolTip {
                            id: editToolTip
                            text: pluginApi?.tr("panel.todo_item.edit_button_tooltip")
                            delay: 1000
                            parent: editButtonIcon
                            visible: editMouseArea.containsMouse

                            contentItem: NText {
                              text: editToolTip.text
                              color: Color.mOnPrimary
                              font.pointSize: Style.fontSizeXS
                            }

                            background: Rectangle {
                              color: Color.mPrimary
                              radius: Style.iRadiusS
                              border.color: Qt.rgba(0, 0, 0, 0.2)
                              border.width: 1
                            }
                          }

                          states: [
                            State {
                              name: "hovered"
                              when: editMouseArea.containsMouse
                              PropertyChanges {
                                target: editButtonIcon
                                opacity: 1.0
                                color: Color.mPrimary
                              }
                            }
                          ]

                          transitions: [
                            Transition {
                              from: "*"
                              to: "hovered"
                              NumberAnimation {
                                properties: "opacity"
                                duration: 150
                              }
                            },
                            Transition {
                              from: "hovered"
                              to: "*"
                              NumberAnimation {
                                properties: "opacity"
                                duration: 150
                              }
                            }
                          ]
                        }
                      }
                    }

                    // Save/Cancel buttons (only show when editing)
                    Item {
                      implicitWidth: Style.baseWidgetSize * 0.8
                      implicitHeight: Style.baseWidgetSize * 0.8
                      visible: delegateItem.editing

                      RowLayout {
                        id: editButtonsRow
                        anchors.centerIn: parent
                        spacing: Style.baseWidgetSize * 0.1

                        // Save button
                        Item {
                          implicitWidth: Style.baseWidgetSize * 1.0
                          implicitHeight: Style.baseWidgetSize * 1.0

                          NIcon {
                            id: saveButtonIcon
                            anchors.centerIn: parent
                            icon: "check"
                            pointSize: Style.fontSizeM
                            color: Color.mOnSurfaceVariant
                            opacity: 0.5

                            MouseArea {
                              id: saveMouseArea
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: {
                                delegateItem.saveEdit();
                              }

                              states: [
                                State {
                                  name: "hovered"
                                  when: saveMouseArea.containsMouse
                                  PropertyChanges {
                                    target: saveButtonIcon
                                    opacity: 1.0
                                    color: Color.mPrimary
                                  }
                                }
                              ]

                              transitions: [
                                Transition {
                                  from: "*"
                                  to: "hovered"
                                  NumberAnimation {
                                    properties: "opacity"
                                    duration: 150
                                  }
                                },
                                Transition {
                                  from: "hovered"
                                  to: "*"
                                  NumberAnimation {
                                    properties: "opacity"
                                    duration: 150
                                  }
                                }
                              ]
                            }
                          }
                        }

                        // Cancel button
                        Item {
                          implicitWidth: Style.baseWidgetSize * 1.0
                          implicitHeight: Style.baseWidgetSize * 1.0

                          NIcon {
                            id: cancelButtonIcon
                            anchors.centerIn: parent
                            icon: "x"
                            pointSize: Style.fontSizeM
                            color: Color.mOnSurfaceVariant
                            opacity: 0.5

                            MouseArea {
                              id: cancelMouseArea
                              anchors.fill: parent
                              hoverEnabled: true
                              cursorShape: Qt.PointingHandCursor
                              onClicked: {
                                delegateItem.cancelEdit();
                              }

                              states: [
                                State {
                                  name: "hovered"
                                  when: cancelMouseArea.containsMouse
                                  PropertyChanges {
                                    target: cancelButtonIcon
                                    opacity: 1.0
                                    color: Color.mOnSurface
                                  }
                                }
                              ]

                              transitions: [
                                Transition {
                                  from: "*"
                                  to: "hovered"
                                  NumberAnimation {
                                    properties: "opacity"
                                    duration: 150
                                  }
                                },
                                Transition {
                                  from: "hovered"
                                  to: "*"
                                  NumberAnimation {
                                    properties: "opacity"
                                    duration: 150
                                  }
                                }
                              ]
                            }
                          }
                        }
                      }
                    }

                    // Delete button
                    Item {
                      id: deleteButtonContainer
                      implicitWidth: Style.baseWidgetSize * 0.8
                      implicitHeight: Style.baseWidgetSize * 0.8

                      NIcon {
                        id: deleteButtonIcon
                        anchors.centerIn: parent
                        icon: "x"
                        pointSize: Style.fontSizeM
                        color: Color.mOnSurfaceVariant
                        opacity: 0.5
                        visible: !delegateItem.editing

                        MouseArea {
                          id: mouseArea
                          anchors.fill: parent
                          hoverEnabled: true
                          cursorShape: Qt.PointingHandCursor
                          onClicked: {
                            removeTodo(modelData.id);
                          }
                        }

                        ToolTip {
                          id: deleteToolTip
                          text: pluginApi?.tr("panel.todo_item.delete_button_tooltip")
                          delay: 1000
                          parent: deleteButtonIcon
                          visible: mouseArea.containsMouse

                          contentItem: NText {
                            text: deleteToolTip.text
                            color: Color.mOnError
                            font.pointSize: Style.fontSizeXS
                          }

                          background: Rectangle {
                            color: Color.mError
                            radius: Style.iRadiusS
                            border.color: Qt.rgba(0, 0, 0, 0.2)
                            border.width: 1
                          }
                        }

                        states: [
                          State {
                            name: "hovered"
                            when: mouseArea.containsMouse
                            PropertyChanges {
                              target: deleteButtonIcon
                              opacity: 1.0
                              color: Color.mError
                            }
                          }
                        ]

                        transitions: [
                          Transition {
                            from: "*"
                            to: "hovered"
                            NumberAnimation {
                              properties: "opacity"
                              duration: 150
                            }
                          },
                          Transition {
                            from: "hovered"
                            to: "*"
                            NumberAnimation {
                              properties: "opacity"
                              duration: 150
                            }
                          }
                        ]
                      }
                    }
                  }

                  // Inline subtask dropdown
                  Column {
                    visible: delegateItem.subtasksExpanded && modelData.subtaskCount > 0
                    clip: true
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.top: mainTaskRow.bottom
                    anchors.leftMargin: Style.marginM + Math.round(Style.baseWidgetSize * 0.5) + Style.marginS + 4 + Style.marginS + Math.round(Style.baseWidgetSize * 0.7) + Style.marginS
                    anchors.rightMargin: Style.marginM
                    spacing: 2

                    Repeater {
                      model: delegateItem.subtaskItems

                      delegate: RowLayout {
                        width: parent.width
                        height: delegateItem.subtaskRowH
                        required property var modelData

                        Rectangle {
                          width: 14; height: 14
                          radius: 2
                          color: modelData.completed ? Color.mPrimary : "transparent"
                          border.color: Color.mOutline
                          border.width: 1

                          NIcon {
                            visible: modelData.completed
                            anchors.centerIn: parent
                            icon: "check"
                            color: Color.mOnPrimary
                            pointSize: Style.fontSizeXS
                          }

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: updateTodo(modelData.id, { completed: !modelData.completed })
                          }
                        }

                        NText {
                          text: modelData.text
                          font.pointSize: Style.fontSizeS
                          font.strikeout: modelData.completed
                          color: modelData.completed ? Color.mOnSurfaceVariant : Color.mOnSurface
                          Layout.fillWidth: true
                          elide: Text.ElideRight
                        }

                        NIcon {
                          icon: "x"
                          pointSize: Style.fontSizeS
                          color: Color.mOnSurfaceVariant
                          opacity: 0.5

                          MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: removeTodo(modelData.id)
                            onContainsMouseChanged: parent.opacity = containsMouse ? 1.0 : 0.5
                          }
                        }
                      }
                    }
                  }
                }
              }

              highlightRangeMode: ListView.NoHighlightRange
              preferredHighlightBegin: 0
              preferredHighlightEnd: 0

              header: null
            }

            // Empty state overlay
              NText {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: -40
                visible: root.filteredTodosModel.count === 0 && root.showEmptyState
                text: pluginApi?.tr("panel.empty_state.message")
                color: Color.mOnSurfaceVariant
                font.pointSize: Style.fontSizeM
                font.weight: Font.Normal
              }
            } // end fillHeight Item

            // ── Completed section ──────────────────────────────────────
            // Header row: "▶/▼ Completed (N)" — only when there are completed todos
            Rectangle {
              Layout.fillWidth: true
              Layout.preferredHeight: Style.baseWidgetSize * 0.85
              visible: root.filteredCompletedModel.count > 0
              color: "transparent"

              RowLayout {
                anchors.fill: parent
                spacing: Style.marginS

                NIcon {
                  icon: root.showCompleted ? "chevron-down" : "chevron-right"
                  pointSize: Style.fontSizeS
                  color: Color.mOnSurfaceVariant
                }

                NText {
                  text: pluginApi?.tr("panel.completed_section.title") + " (" + root.filteredCompletedModel.count + ")"
                  color: Color.mOnSurfaceVariant
                  font.pointSize: Style.fontSizeS
                }

                Item { Layout.fillWidth: true }
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.showCompleted = !root.showCompleted;
                  pluginApi.pluginSettings.showCompleted = root.showCompleted;
                  pluginApi.saveSettings();
                }
              }
            }

            // Completed tasks list
            ListView {
              id: completedListView
              Layout.fillWidth: true
              Layout.preferredHeight: Math.min(
                root.filteredCompletedModel.count * (Style.baseWidgetSize + Style.marginS),
                180
              )
              clip: true
              visible: root.showCompleted && root.filteredCompletedModel.count > 0
              model: root.filteredCompletedModel
              spacing: Style.marginS
              boundsBehavior: Flickable.StopAtBounds

              delegate: Rectangle {
                width: ListView.view.width
                height: Style.baseWidgetSize
                color: Color.mSurface
                radius: Style.radiusS
                required property var modelData

                MouseArea {
                  anchors.fill: parent
                  onClicked: root.openTodoDetails(modelData)
                }

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: Style.marginM
                  anchors.rightMargin: Style.marginM
                  spacing: Style.marginS

                  // Priority colour bar
                  Rectangle {
                    Layout.preferredWidth: 4
                    Layout.preferredHeight: parent.height - Style.marginS
                    Layout.alignment: Qt.AlignVCenter
                    radius: 2
                    color: getPriorityColor(modelData.priority || "medium")
                  }

                  // Filled checkbox
                  Item {
                    Layout.preferredWidth: Style.baseWidgetSize * 0.7
                    Layout.preferredHeight: Style.baseWidgetSize * 0.7

                    Rectangle {
                      anchors.fill: parent
                      radius: Style.iRadiusXS
                      color: Color.mPrimary
                      border.color: Color.mOutline
                      border.width: Style.borderS

                      NIcon {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -1
                        icon: "check"
                        color: Color.mOnPrimary
                        pointSize: Math.max(Style.fontSizeXS, Style.baseWidgetSize * 0.7 * 0.5)
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: toggleTodo(modelData.id, true)
                      }
                    }
                  }

                  // Strikethrough text
                  NText {
                    Layout.fillWidth: true
                    text: modelData.text
                    color: Color.mOnSurfaceVariant
                    font.strikeout: true
                    elide: Text.ElideRight
                    verticalAlignment: Text.AlignVCenter
                  }

                  // Delete button
                  NIcon {
                    icon: "x"
                    pointSize: Style.fontSizeM
                    color: Color.mOnSurfaceVariant
                    opacity: 0.5

                    MouseArea {
                      anchors.fill: parent
                      hoverEnabled: true
                      cursorShape: Qt.PointingHandCursor
                      onClicked: removeTodo(modelData.id)
                      onContainsMouseChanged: parent.opacity = containsMouse ? 1.0 : 0.5
                    }
                  }
                }
              }
            }

          }
        }
      }
    }
  }

  // Dialog for displaying todo details
  Popup {
    id: detailDialog

    property var todoId: 0
    property string todoText: ""
    property bool todoCompleted: false
    property string todoCreatedAt: ""
    property int todoPageId: 0
    property string todoPriority: "medium"
    property string todoDetails: ""
    property string todoDueDate: ""

    x: 10
    y: (parent.height - height) / 2
    width: parent.width - 20
    height: Math.min(520 * Style.uiScaleRatio, parent.height - 20)
    modal: true
    focus: true
    padding: 0

    ListModel { id: subtasksModel }

    function refreshSubtasks() {
      subtasksModel.clear();
      var pid = String(detailDialog.todoId);
      var todos = root.rawTodos || [];
      for (var i = 0; i < todos.length; i++) {
        var t = todos[i];
        if (String(t.parentId) === pid) {
          subtasksModel.append({
            id: t.id, text: t.text,
            completed: t.completed === true,
            parentId: String(t.parentId)
          });
        }
      }
    }

    onOpened: refreshSubtasks()

    Connections {
      target: root
      function onRawTodosChanged() {
        if (detailDialog.visible) detailDialog.refreshSubtasks();
      }
    }

    // Background
    background: Rectangle {
      color: Color.mSurface
      radius: Style.radiusL
      border.color: Color.mOutline
      border.width: 1
    }

    // Content
    contentItem: Item {
      anchors.fill: parent

      // Header bar
      Rectangle {
        id: headerBar
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 44 * Style.uiScaleRatio
        color: Color.mPrimary
        radius: Style.radiusS

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Style.marginL
          anchors.rightMargin: Style.marginM

          NText {
            text: pluginApi?.tr("panel.todo_details.title")
            font.pointSize: Style.fontSizeM
            font.weight: Font.Bold
            color: Color.mOnPrimary
            Layout.fillWidth: true
          }

          NIconButton {
            icon: "x"
            colorBg: Qt.rgba(1, 1, 1, 0.2)
            colorBgHover: Qt.rgba(1, 1, 1, 0.3)
            colorFg: Color.mOnPrimary
            onClicked: detailDialog.close()
          }
        }
      }

      // Scrollable content (below header)
      Flickable {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: headerBar.bottom
        anchors.bottom: parent.bottom
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + Style.marginL
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
          id: contentColumn
          anchors.fill: parent
          anchors.leftMargin: Style.marginL
          anchors.rightMargin: Style.marginL
          anchors.topMargin: Style.marginM
          anchors.bottomMargin: Style.marginM
          spacing: Style.marginM

          // Todo text
          NText {
            text: detailDialog.todoText
            font.pointSize: Style.fontSizeL
            font.weight: Font.Bold
            color: Color.mOnSurface
            wrapMode: Text.Wrap
            Layout.fillWidth: true
          }

          // Details section with add/edit button
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            // Divider before details
            Rectangle {
              height: 1
              color: Color.mOutline
              opacity: 0.3
              Layout.fillWidth: true
            }

            // Label + Add/Edit button row
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS

              NText {
                text: pluginApi?.tr("panel.todo_details.label_details")
                font.pointSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
                Layout.preferredWidth: 80 * Style.uiScaleRatio
                Layout.alignment: Qt.AlignVCenter
              }

              // Spacer to push button to the right
              Item {
                Layout.fillWidth: true
              }

              NButton {
                text: detailDialog.todoDetails.length > 0 ? pluginApi?.tr("panel.todo_details.button_edit_details") : pluginApi?.tr("panel.todo_details.button_add_details")
                icon: "pencil"
                backgroundColor: Color.mSurfaceVariant
                textColor: Color.mOnSurface
                fontSize: Style.fontSizeS
                outlined: true
                onClicked: {
                  detailsEditMode = true;
                  Qt.callLater(function () {
                    detailsTextArea.text = detailDialog.todoDetails;
                    detailsTextArea.forceActiveFocus();
                  });
                }
              }
            }

            // View mode (show details if not empty)
            NText {
              text: detailDialog.todoDetails
              font.pointSize: Style.fontSizeS
              color: Color.mOnSurface
              wrapMode: Text.Wrap
              Layout.fillWidth: true
              visible: detailDialog.todoDetails.length > 0 && !detailsEditMode
            }

            // Edit mode (TextArea)
            TextArea {
              id: detailsTextArea
              visible: detailsEditMode
              text: detailDialog.todoDetails
              Layout.fillWidth: true
              Layout.preferredHeight: 100
              wrapMode: TextArea.Wrap
              color: Color.mOnSurface
              background: Rectangle {
                color: Color.mSurfaceVariant
                radius: Style.iRadiusS
              }
              Keys.onEscapePressed: {
                detailsEditMode = false;
              }
            }

            // Save/Cancel buttons for details edit
            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS
              visible: detailsEditMode

              NButton {
                text: pluginApi?.tr("panel.todo_details.button_save")
                backgroundColor: Color.mPrimary
                onClicked: {
                  updateTodo(detailDialog.todoId, {
                               details: detailsTextArea.text
                             });
                  detailDialog.todoDetails = detailsTextArea.text;
                  detailsEditMode = false;
                }
              }

              NButton {
                text: pluginApi?.tr("panel.todo_details.button_cancel")
                backgroundColor: Color.mSurfaceVariant
                onClicked: {
                  detailsEditMode = false;
                }
              }
            }
          }

          // Divider
          Rectangle {
            height: 1
            color: Color.mOutline
            opacity: 0.3
            Layout.fillWidth: true
          }

          // Details
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            // Page
            RowLayout {
              spacing: Style.marginS
              Layout.fillWidth: true

              NText {
                text: pluginApi?.tr("panel.todo_details.label_page")
                font.pointSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
                Layout.preferredWidth: 80 * Style.uiScaleRatio
                Layout.alignment: Qt.AlignTop
              }

              NText {
                text: getPageName(detailDialog.todoPageId)
                font.pointSize: Style.fontSizeS
                font.weight: Font.Medium
                color: Color.mOnSurface
                Layout.alignment: Qt.AlignTop
              }
            }

            // Status
            RowLayout {
              spacing: Style.marginS
              Layout.fillWidth: true

              NText {
                text: pluginApi?.tr("panel.todo_details.label_status")
                font.pointSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
                Layout.preferredWidth: 80 * Style.uiScaleRatio
                Layout.alignment: Qt.AlignTop
              }

              NText {
                text: detailDialog.todoCompleted ? pluginApi?.tr("panel.todo_details.status_completed") : pluginApi?.tr("panel.todo_details.status_pending")
                font.pointSize: Style.fontSizeS
                font.weight: Font.Medium
                color: detailDialog.todoCompleted ? Color.mPrimary : Color.mError
                Layout.alignment: Qt.AlignTop
              }
            }

            // Priority
            RowLayout {
              spacing: Style.marginS
              Layout.fillWidth: true

              NText {
                text: pluginApi?.tr("panel.todo_details.label_priority")
                font.pointSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
                Layout.preferredWidth: 82 * Style.uiScaleRatio
                Layout.alignment: Qt.AlignTop
              }

              // Priority selector with H/M/L buttons
              RowLayout {
                spacing: Style.marginXS

                // High priority button
                Rectangle {
                  width: 28
                  height: 28
                  radius: 4
                  color: detailDialog.todoPriority === "high" ? getPriorityColor("high") : Qt.rgba(getPriorityColor("high").r, getPriorityColor("high").g, getPriorityColor("high").b, 0.2)
                  border.color: detailDialog.todoPriority === "high" ? getPriorityColor("high") : "transparent"
                  border.width: 2

                  NText {
                    anchors.centerIn: parent
                    text: "H"
                    color: detailDialog.todoPriority === "high" ? Color.mOnPrimary : getPriorityColor("high")
                    font.pointSize: Style.fontSizeS
                    font.weight: Font.Bold
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      updateTodo(detailDialog.todoId, {
                                   priority: "high"
                                 });
                      detailDialog.todoPriority = "high";
                    }
                  }
                }

                // Medium priority button
                Rectangle {
                  width: 28
                  height: 28
                  radius: 4
                  color: detailDialog.todoPriority === "medium" ? getPriorityColor("medium") : Qt.rgba(getPriorityColor("medium").r, getPriorityColor("medium").g, getPriorityColor("medium").b, 0.2)
                  border.color: detailDialog.todoPriority === "medium" ? getPriorityColor("medium") : "transparent"
                  border.width: 2

                  NText {
                    anchors.centerIn: parent
                    text: "M"
                    color: detailDialog.todoPriority === "medium" ? Color.mOnPrimary : getPriorityColor("medium")
                    font.pointSize: Style.fontSizeS
                    font.weight: Font.Bold
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      updateTodo(detailDialog.todoId, {
                                   priority: "medium"
                                 });
                      detailDialog.todoPriority = "medium";
                    }
                  }
                }

                // Low priority button
                Rectangle {
                  width: 28
                  height: 28
                  radius: 4
                  color: detailDialog.todoPriority === "low" ? getPriorityColor("low") : Qt.rgba(getPriorityColor("low").r, getPriorityColor("low").g, getPriorityColor("low").b, 0.2)
                  border.color: detailDialog.todoPriority === "low" ? getPriorityColor("low") : "transparent"
                  border.width: 2

                  NText {
                    anchors.centerIn: parent
                    text: "L"
                    color: detailDialog.todoPriority === "low" ? Color.mOnPrimary : getPriorityColor("low")
                    font.pointSize: Style.fontSizeS
                    font.weight: Font.Bold
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                      updateTodo(detailDialog.todoId, {
                                   priority: "low"
                                 });
                      detailDialog.todoPriority = "low";
                    }
                  }
                }
              }
            }

            // Due date
            RowLayout {
              spacing: Style.marginS
              Layout.fillWidth: true

              NText {
                text: pluginApi?.tr("panel.todo_details.label_due_date")
                font.pointSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
                Layout.preferredWidth: 80 * Style.uiScaleRatio
                Layout.alignment: Qt.AlignVCenter
              }

              TextField {
                id: dueDateField
                text: detailDialog.todoDueDate
                placeholderText: "YYYY-MM-DD"
                Layout.fillWidth: true
                font.pointSize: Style.fontSizeS
                color: Color.mOnSurface
                leftPadding: Style.marginS
                rightPadding: Style.marginS
                background: Rectangle {
                  color: Color.mSurfaceVariant
                  radius: Style.iRadiusS
                }
                onEditingFinished: {
                  var val = dueDateField.text.trim();
                  if (val === "" || /^\d{4}-\d{2}-\d{2}$/.test(val)) {
                    updateTodo(detailDialog.todoId, { dueDate: val });
                    detailDialog.todoDueDate = val;
                  }
                }
              }

              NIconButton {
                icon: "x"
                baseSize: Style.baseWidgetSize * 0.8
                visible: detailDialog.todoDueDate !== ""
                onClicked: {
                  updateTodo(detailDialog.todoId, { dueDate: "" });
                  detailDialog.todoDueDate = "";
                  dueDateField.text = "";
                }
              }
            }

            // Created date
            RowLayout {
              spacing: Style.marginS
              Layout.fillWidth: true

              NText {
                text: pluginApi?.tr("panel.todo_details.label_created")
                font.pointSize: Style.fontSizeS
                color: Color.mOnSurfaceVariant
                Layout.preferredWidth: 80 * Style.uiScaleRatio
                Layout.alignment: Qt.AlignTop
              }

              NText {
                text: new Date(detailDialog.todoCreatedAt).toLocaleString()
                font.pointSize: Style.fontSizeS
                color: Color.mOnSurface
                wrapMode: Text.Wrap
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
              }
            }
          }

          // ── Subtasks section ───────────────────────────────────────────
          ColumnLayout {
            Layout.fillWidth: true
            spacing: Style.marginS

            Rectangle {
              height: 1
              color: Color.mOutline
              opacity: 0.3
              Layout.fillWidth: true
            }

            NText {
              text: pluginApi?.tr("panel.todo_details.label_subtasks")
              font.pointSize: Style.fontSizeS
              color: Color.mOnSurfaceVariant
            }

            Repeater {
              model: subtasksModel

              delegate: RowLayout {
                Layout.fillWidth: true
                spacing: Style.marginS
                required property var modelData
                required property int index

                Rectangle {
                  width: 18; height: 18
                  radius: 3
                  color: modelData.completed ? Color.mPrimary : "transparent"
                  border.color: Color.mOutline
                  border.width: 1

                  NIcon {
                    visible: modelData.completed
                    anchors.centerIn: parent
                    icon: "check"
                    color: Color.mOnPrimary
                    pointSize: Style.fontSizeXS
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: updateTodo(modelData.id, { completed: !modelData.completed })
                  }
                }

                NText {
                  text: modelData.text
                  font.pointSize: Style.fontSizeS
                  font.strikeout: modelData.completed
                  color: modelData.completed ? Color.mOnSurfaceVariant : Color.mOnSurface
                  Layout.fillWidth: true
                  elide: Text.ElideRight
                }

                NIcon {
                  icon: "x"
                  pointSize: Style.fontSizeS
                  color: Color.mOnSurfaceVariant
                  opacity: 0.5

                  MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: removeTodo(modelData.id)
                    onContainsMouseChanged: parent.opacity = containsMouse ? 1.0 : 0.5
                  }
                }
              }
            }

            RowLayout {
              Layout.fillWidth: true
              spacing: Style.marginS

              NTextInput {
                id: newSubtaskInput
                placeholderText: pluginApi?.tr("panel.todo_details.add_subtask_placeholder")
                Layout.fillWidth: true
                Keys.onReturnPressed: {
                  var t = newSubtaskInput.text.trim();
                  if (t && mainInstance) {
                    mainInstance.addSubtask(detailDialog.todoId, t);
                    newSubtaskInput.text = "";
                  }
                }
              }

              NIconButton {
                icon: "plus"
                baseSize: Style.baseWidgetSize * 0.9
                onClicked: {
                  var t = newSubtaskInput.text.trim();
                  if (t && mainInstance) {
                    mainInstance.addSubtask(detailDialog.todoId, t);
                    newSubtaskInput.text = "";
                  }
                }
              }
            }
          }
        }
      }
    }
  }

  function addTodo() {
    var text = newTodoInput.text.trim();
    if (!text || !mainInstance)
      return;

    var currentPageId = pluginApi?.pluginSettings?.current_page_id || 0;
    mainInstance.createTodo(text, priorityGroup.currentPriority, currentPageId);
    newTodoInput.text = "";
  }

  // Internal utility functions
  function updateTodo(todoId, updates) {
    if (!mainInstance)
      return false;
    return mainInstance.updateTodo(todoId, updates);
  }

  // Helper function to remove a todo by ID
  function removeTodo(todoId) {
    if (!mainInstance) {
      Logger.e("Todo", "mainInstance is null, cannot delete todo");
      return false;
    }
    return mainInstance.deleteTodo(todoId);
  }

  // Helper function to toggle todo completion status
  function toggleTodo(todoId, currentCompletedStatus) {
    if (!mainInstance) {
      Logger.e("Todo", "mainInstance is null, cannot toggle todo");
      return false;
    }

    // Use the existing updateTodo function to update only the completion status
    return updateTodo(todoId, {
                        completed: !currentCompletedStatus
                      });
  }

  // Helper function to clear completed todos for the current page
  function clearCompletedTodos() {
    var currentPageId = pluginApi?.pluginSettings?.current_page_id || 0;

    // Get all todos (rawTodos is synced via Binding from pluginSettings)
    var todos = root.rawTodos || [];
    var removedCount = 0;

    // Remove completed todos from current page
    for (var i = todos.length - 1; i >= 0; i--) {
      if (todos[i].completed && todos[i].pageId === currentPageId) {
        mainInstance.deleteTodo(todos[i].id);
        removedCount++;
      }
    }

    return removedCount;
  }

  // Helper function to move todo by index (for drag reorder)
  function moveTodoItem(fromIndex: int, toIndex: int) {
    if (!mainInstance) {
      Logger.e("Todo", "mainInstance is null, cannot move todo");
      return;
    }
    mainInstance.moveTodoItem(fromIndex, toIndex);
  }

  // Helper function to get priority color
  function getPriorityColor(priority) {
    // Validate priority
    var validPriorities = ["high", "medium", "low"];
    if (!priority || validPriorities.indexOf(priority) === -1) {
      priority = "medium";
    }

    if (!pluginApi) {
      return getThemeColor(priority);
    }

    var useCustomColors = pluginApi?.pluginSettings?.useCustomColors;
    if (useCustomColors) {
      var customColors = pluginApi?.pluginSettings?.priorityColors;
      if (customColors && customColors[priority]) {
        return customColors[priority];
      }
    }

    return getThemeColor(priority);
  }

  // Helper function to get theme color
  function getThemeColor(priority) {
    if (priority === "high")
      return Color.mError;
    if (priority === "low")
      return Color.mOnSurfaceVariant;
    return Color.mPrimary;
  }

  // Helper function to get page name by ID
  function getPageName(pageId) {
    var pages = pluginApi?.pluginSettings?.pages || [];
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].id === pageId) {
        return pages[i].name;
      }
    }
    return "Unknown";
  }

  function formatDueDate(dateStr) {
    if (!dateStr) return "";
    var d = new Date(dateStr);
    var today = new Date();
    today.setHours(0, 0, 0, 0);
    var due = new Date(d.getFullYear(), d.getMonth(), d.getDate());
    var diff = Math.round((due - today) / 86400000);
    if (diff < 0)  return "overdue";
    if (diff === 0) return "today";
    if (diff === 1) return "tmrw";
    if (diff < 7)  return diff + "d";
    return d.toLocaleDateString(undefined, { month: "short", day: "numeric" });
  }

  function isDueOverdue(dateStr) {
    if (!dateStr) return false;
    var today = new Date();
    today.setHours(0, 0, 0, 0);
    return new Date(dateStr) < today;
  }

  function isDueToday(dateStr) {
    if (!dateStr) return false;
    var d = new Date(dateStr);
    var t = new Date();
    return d.getFullYear() === t.getFullYear() && d.getMonth() === t.getMonth() && d.getDate() === t.getDate();
  }

  // Function to open the detailed view for a todo item
  function openTodoDetails(todo) {
    detailsEditMode = false;

    // Fill the detail dialog with the todo's information
    detailDialog.todoId = todo.id;
    detailDialog.todoText = todo.text;
    detailDialog.todoCompleted = todo.completed;
    detailDialog.todoCreatedAt = todo.createdAt;
    detailDialog.todoPageId = todo.pageId;
    detailDialog.todoPriority = todo.priority;
    detailDialog.todoDetails = todo.details || "";
    detailDialog.todoDueDate = todo.dueDate || "";

    detailDialog.open();
  }

  function loadTodos() {
    // Store the current scroll position and visible item
    var currentScrollPos = todoListView ? todoListView.contentY : 0;
    var currentVisibleIndex = todoListView ? todoListView.currentIndex : -1;

    // Clear both models
    filteredTodosModel.clear();
    filteredCompletedModel.clear();

    var pluginTodos = root.rawTodos;
    var currentPageId = root.currentPageId;

    // Split todos into active and completed models
    for (var i = 0; i < pluginTodos.length; i++) {
      var todo = pluginTodos[i];
      if (todo.pageId === currentPageId && !todo.parentId) {
        var subtaskCount = 0;
        for (var j = 0; j < pluginTodos.length; j++) {
          if (String(pluginTodos[j].parentId) === String(todo.id)) subtaskCount++;
        }
        var todoItem = {
          id: todo.id,
          text: todo.text,
          completed: todo.completed === true,
          createdAt: todo.createdAt,
          pageId: todo.pageId,
          priority: todo.priority,
          details: todo.details,
          dueDate: todo.dueDate || "",
          parentId: todo.parentId || "",
          subtaskCount: subtaskCount
        };

        if (todo.completed) {
          filteredCompletedModel.append(todoItem);
        } else {
          filteredTodosModel.append(todoItem);
        }
      }
    }

    // Restore the scroll position and visible item
    if (todoListView) {
      Qt.callLater(function () {
        if (currentVisibleIndex >= 0 && currentVisibleIndex < filteredTodosModel.count) {
          todoListView.positionViewAtIndex(currentVisibleIndex, ListView.Beginning);
        } else if (currentScrollPos > 0) {
          todoListView.contentY = currentScrollPos;
        }
      });
    }

    // Check if the model is empty
    root.showEmptyState = (filteredTodosModel.count === 0);

    // Restore the scroll position
    if (todoListView) {
      Qt.callLater(function () {
        todoListView.contentY = currentScrollPos;
      });
    }

    // Check if the model is empty
    root.showEmptyState = (filteredTodosModel.count === 0);
  }
}
