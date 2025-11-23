package main

import (
	"encoding/json"
	"fmt"
	"log"
	"os/exec"
	"strings"
	"time"

	ui "github.com/gizak/termui/v3"
	"github.com/gizak/termui/v3/widgets"
)

type Service struct {
	Name      string `json:"name"`
	Label     string `json:"label"`
	Status    string `json:"status"`
	Health    string `json:"health"`
	StartedAt string `json:"started_at"`
	Image     string `json:"image"`
	ExitCode  string `json:"exit_code"`
}

type ContainerStats struct {
	CPU           float64 `json:"cpu"`
	Memory        string  `json:"memory"`
	MemoryPercent float64 `json:"memory_percent"`
}

type Port struct {
	Name      string `json:"name"`
	Port      string `json:"port"`
	Reachable bool   `json:"reachable"`
}

type DirInfo struct {
	Path   string `json:"path"`
	Exists bool   `json:"exists"`
	Size   string `json:"size"`
}

type VolumeInfo struct {
	Name       string `json:"name"`
	Exists     bool   `json:"exists"`
	Mountpoint string `json:"mountpoint"`
}

type UserStats struct {
	Accounts   int `json:"accounts"`
	Online     int `json:"online"`
	Characters int `json:"characters"`
	Active7d   int `json:"active7d"`
}

type Module struct {
	Name        string `json:"name"`
	Key         string `json:"key"`
	Description string `json:"description"`
	Category    string `json:"category"`
	Type        string `json:"type"`
}

type Snapshot struct {
	Timestamp string                    `json:"timestamp"`
	Project   string                    `json:"project"`
	Network   string                    `json:"network"`
	Services  []Service                 `json:"services"`
	Ports     []Port                    `json:"ports"`
	Modules   []Module                  `json:"modules"`
	Storage   map[string]DirInfo        `json:"storage"`
	Volumes   map[string]VolumeInfo     `json:"volumes"`
	Users     UserStats                 `json:"users"`
	Stats     map[string]ContainerStats `json:"stats"`
}

var persistentServiceOrder = []string{
	"ac-mysql",
	"ac-db-guard",
	"ac-authserver",
	"ac-worldserver",
	"ac-phpmyadmin",
	"ac-keira3",
	"ac-backup",
}

func runSnapshot() (*Snapshot, error) {
	cmd := exec.Command("./scripts/bash/statusjson.sh")
	output, err := cmd.Output()
	if err != nil {
		return nil, err
	}
	snap := &Snapshot{}
	if err := json.Unmarshal(output, snap); err != nil {
		return nil, err
	}
	return snap, nil
}

func partitionServices(all []Service) ([]Service, []Service) {
	byName := make(map[string]Service)
	for _, svc := range all {
		byName[svc.Name] = svc
	}

	seen := make(map[string]bool)
	persistent := make([]Service, 0, len(persistentServiceOrder))
	for _, name := range persistentServiceOrder {
		if svc, ok := byName[name]; ok {
			persistent = append(persistent, svc)
			seen[name] = true
		}
	}

	setups := make([]Service, 0, len(all))
	for _, svc := range all {
		if seen[svc.Name] {
			continue
		}
		setups = append(setups, svc)
	}
	return persistent, setups
}

func buildServicesTable(s *Snapshot) *TableNoCol {
	runningServices, setupServices := partitionServices(s.Services)

	table := NewTableNoCol()
	rows := [][]string{{"Group", "Service", "Status", "Health", "CPU%", "Memory"}}
	appendRows := func(groupLabel string, services []Service) {
		for _, svc := range services {
			cpu := "-"
			mem := "-"
			if svcStats, ok := s.Stats[svc.Name]; ok {
				cpu = fmt.Sprintf("%.1f", svcStats.CPU)
				mem = strings.Split(svcStats.Memory, " / ")[0] // Just show used, not total
			}
			health := svc.Health
			if svc.Status != "running" && svc.ExitCode != "0" && svc.ExitCode != "" {
				health = fmt.Sprintf("%s (%s)", svc.Health, svc.ExitCode)
			}
			rows = append(rows, []string{groupLabel, svc.Label, svc.Status, health, cpu, mem})
		}
	}

	appendRows("Persistent", runningServices)
	appendRows("Setup", setupServices)

	table.Rows = rows
	table.RowSeparator = false
	table.Border = true
	table.Title = "Services"

	for i := 1; i < len(table.Rows); i++ {
		if table.RowStyles == nil {
			table.RowStyles = make(map[int]ui.Style)
		}
		state := strings.ToLower(table.Rows[i][2])
		switch state {
		case "running", "healthy":
			table.RowStyles[i] = ui.NewStyle(ui.ColorGreen)
		case "restarting", "unhealthy":
			table.RowStyles[i] = ui.NewStyle(ui.ColorRed)
		case "exited":
			table.RowStyles[i] = ui.NewStyle(ui.ColorYellow)
		default:
			table.RowStyles[i] = ui.NewStyle(ui.ColorWhite)
		}
	}
	return table
}

func buildPortsTable(s *Snapshot) *TableNoCol {
	table := NewTableNoCol()
	rows := [][]string{{"Port", "Number", "Reachable"}}
	for _, p := range s.Ports {
		state := "down"
		if p.Reachable {
			state = "up"
		}
		rows = append(rows, []string{p.Name, p.Port, state})
	}
	table.Rows = rows
	table.RowSeparator = true
	table.Border = true
	table.Title = "Ports"
	return table
}

func buildModulesList(s *Snapshot) *widgets.List {
	list := widgets.NewList()
	list.Title = fmt.Sprintf("Modules (%d)", len(s.Modules))
	rows := make([]string, len(s.Modules))
	for i, mod := range s.Modules {
		rows[i] = mod.Name
	}
	list.Rows = rows
	list.WrapText = false
	list.Border = true
	list.BorderStyle = ui.NewStyle(ui.ColorCyan)
	list.SelectedRowStyle = ui.NewStyle(ui.ColorCyan)
	return list
}

func buildStorageParagraph(s *Snapshot) *widgets.Paragraph {
	var b strings.Builder
	entries := []struct {
		Key   string
		Label string
	}{
		{"storage", "Storage"},
		{"local_storage", "Local Storage"},
		{"client_data", "Client Data"},
		{"modules", "Modules"},
		{"local_modules", "Local Modules"},
	}
	for _, item := range entries {
		info, ok := s.Storage[item.Key]
		if !ok {
			continue
		}
		fmt.Fprintf(&b, "  %-15s %s (%s)\n", item.Label, info.Path, info.Size)
	}
	par := widgets.NewParagraph()
	par.Title = "Storage"
	par.Text = b.String()
	par.Border = true
	par.BorderStyle = ui.NewStyle(ui.ColorYellow)
	return par
}

func buildVolumesParagraph(s *Snapshot) *widgets.Paragraph {
	var b strings.Builder
	entries := []struct {
		Key   string
		Label string
	}{
		{"client_cache", "Client Cache"},
		{"mysql_data", "MySQL Data"},
	}
	for _, item := range entries {
		info, ok := s.Volumes[item.Key]
		if !ok {
			continue
		}
		fmt.Fprintf(&b, "  %-13s %s\n", item.Label, info.Mountpoint)
	}
	par := widgets.NewParagraph()
	par.Title = "Volumes"
	par.Text = b.String()
	par.Border = true
	par.BorderStyle = ui.NewStyle(ui.ColorYellow)
	return par
}

func renderSnapshot(s *Snapshot, selectedModule int) (*widgets.List, *ui.Grid) {
	servicesTable := buildServicesTable(s)
	portsTable := buildPortsTable(s)
	for i := 1; i < len(portsTable.Rows); i++ {
		if portsTable.RowStyles == nil {
			portsTable.RowStyles = make(map[int]ui.Style)
		}
		if portsTable.Rows[i][2] == "up" {
			portsTable.RowStyles[i] = ui.NewStyle(ui.ColorGreen)
		} else {
			portsTable.RowStyles[i] = ui.NewStyle(ui.ColorRed)
		}
	}
	modulesList := buildModulesList(s)
	if selectedModule >= 0 && selectedModule < len(modulesList.Rows) {
		modulesList.SelectedRow = selectedModule
	}
	helpPar := widgets.NewParagraph()
	helpPar.Title = "Controls"
	helpPar.Text = "  ↓ : Down\n  ↑ : Up"
	helpPar.Border = true
	helpPar.BorderStyle = ui.NewStyle(ui.ColorMagenta)

	moduleInfoPar := widgets.NewParagraph()
	moduleInfoPar.Title = "Module Info"
	if selectedModule >= 0 && selectedModule < len(s.Modules) {
		mod := s.Modules[selectedModule]
		moduleInfoPar.Text = fmt.Sprintf("%s\nCategory: %s\nType: %s", mod.Description, mod.Category, mod.Type)
	} else {
		moduleInfoPar.Text = "Select a module to view info"
	}
	moduleInfoPar.Border = true
	moduleInfoPar.BorderStyle = ui.NewStyle(ui.ColorMagenta)
	storagePar := buildStorageParagraph(s)
	storagePar.Border = true
	storagePar.BorderStyle = ui.NewStyle(ui.ColorYellow)
	storagePar.PaddingLeft = 1
	storagePar.PaddingRight = 1
	volumesPar := buildVolumesParagraph(s)

	header := widgets.NewParagraph()
	header.Text = fmt.Sprintf("Project: %s\nNetwork: %s\nUpdated: %s", s.Project, s.Network, s.Timestamp)
	header.Border = true

	usersPar := widgets.NewParagraph()
	usersPar.Text = fmt.Sprintf("USERS:\n  Accounts: %d\n  Online: %d\n  Characters: %d\n  Active 7d: %d", s.Users.Accounts, s.Users.Online, s.Users.Characters, s.Users.Active7d)
	usersPar.Border = true

	grid := ui.NewGrid()
	termWidth, termHeight := ui.TerminalDimensions()
	grid.SetRect(0, 0, termWidth, termHeight)
	grid.Set(
		ui.NewRow(0.15,
			ui.NewCol(0.6, header),
			ui.NewCol(0.4, usersPar),
		),
		ui.NewRow(0.46,
			ui.NewCol(0.6, servicesTable),
			ui.NewCol(0.4, portsTable),
		),
		ui.NewRow(0.39,
			ui.NewCol(0.25, modulesList),
			ui.NewCol(0.15,
				ui.NewRow(0.30, helpPar),
				ui.NewRow(0.70, moduleInfoPar),
			),
			ui.NewCol(0.6,
				ui.NewRow(0.55,
					ui.NewCol(1.0, storagePar),
				),
				ui.NewRow(0.45,
					ui.NewCol(1.0, volumesPar),
				),
			),
		),
	)
	ui.Render(grid)
	return modulesList, grid
}

func main() {
	if err := ui.Init(); err != nil {
		log.Fatalf("failed to init termui: %v", err)
	}
	defer ui.Close()

	snapshot, err := runSnapshot()
	if err != nil {
		log.Fatalf("failed to fetch snapshot: %v", err)
	}
	selectedModule := 0
	modulesWidget, currentGrid := renderSnapshot(snapshot, selectedModule)

	snapCh := make(chan *Snapshot, 1)
	go func() {
		ticker := time.NewTicker(5 * time.Second)
		defer ticker.Stop()
		for range ticker.C {
			snap, err := runSnapshot()
			if err != nil {
				log.Printf("snapshot error: %v", err)
				continue
			}
			select {
			case snapCh <- snap:
			default:
			}
		}
	}()

	events := ui.PollEvents()
	for {
		select {
		case e := <-events:
			switch e.ID {
			case "q", "<C-c>":
				return
			case "<Down>", "j":
				if selectedModule < len(snapshot.Modules)-1 {
					selectedModule++
					modulesWidget, currentGrid = renderSnapshot(snapshot, selectedModule)
				}
			case "<Up>", "k":
				if selectedModule > 0 {
					selectedModule--
					modulesWidget, currentGrid = renderSnapshot(snapshot, selectedModule)
				}
			case "<Resize>":
				modulesWidget, currentGrid = renderSnapshot(snapshot, selectedModule)
				continue
			}
			if modulesWidget != nil {
				if selectedModule >= 0 && selectedModule < len(modulesWidget.Rows) {
					modulesWidget.SelectedRow = selectedModule
				}
			}
			if currentGrid != nil {
				ui.Render(currentGrid)
			}
		case snap := <-snapCh:
			snapshot = snap
			if selectedModule >= len(snapshot.Modules) {
				selectedModule = len(snapshot.Modules) - 1
				if selectedModule < 0 {
					selectedModule = 0
				}
			}
			modulesWidget, currentGrid = renderSnapshot(snapshot, selectedModule)
		}
	}
}
