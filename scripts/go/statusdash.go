package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net"
	"os"
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

type BuildInfo struct {
	Variant      string `json:"variant"`
	Repo         string `json:"repo"`
	Branch       string `json:"branch"`
	Image        string `json:"image"`
	Commit       string `json:"commit"`
	CommitDate   string `json:"commit_date"`
	CommitSource string `json:"commit_source"`
	SourcePath   string `json:"source_path"`
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
	Build     BuildInfo                 `json:"build"`
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

func humanDuration(d time.Duration) string {
	if d < time.Minute {
		return "<1m"
	}
	days := d / (24 * time.Hour)
	d -= days * 24 * time.Hour
	hours := d / time.Hour
	d -= hours * time.Hour
	mins := d / time.Minute

	switch {
	case days > 0:
		return fmt.Sprintf("%dd %dh", days, hours)
	case hours > 0:
		return fmt.Sprintf("%dh %dm", hours, mins)
	default:
		return fmt.Sprintf("%dm", mins)
	}
}

func formatUptime(startedAt string) string {
	if startedAt == "" {
		return "-"
	}
	parsed, err := time.Parse(time.RFC3339Nano, startedAt)
	if err != nil {
		parsed, err = time.Parse(time.RFC3339, startedAt)
		if err != nil {
			return "-"
		}
	}
	if parsed.IsZero() {
		return "-"
	}
	uptime := time.Since(parsed)
	if uptime < 0 {
		uptime = 0
	}
	return humanDuration(uptime)
}

func primaryIPv4() string {
	ifaces, err := net.Interfaces()
	if err != nil {
		return ""
	}
	for _, iface := range ifaces {
		if iface.Flags&net.FlagUp == 0 || iface.Flags&net.FlagLoopback != 0 {
			continue
		}
		addrs, err := iface.Addrs()
		if err != nil {
			continue
		}
		for _, addr := range addrs {
			var ip net.IP
			switch v := addr.(type) {
			case *net.IPNet:
				ip = v.IP
			case *net.IPAddr:
				ip = v.IP
			}
			if ip == nil || ip.IsLoopback() {
				continue
			}
			ip = ip.To4()
			if ip == nil {
				continue
			}
			return ip.String()
		}
	}
	return ""
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
	rows := [][]string{{"Service", "Status", "Health", "Uptime", "CPU%", "Memory"}}
	appendRows := func(services []Service) {
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
			rows = append(rows, []string{svc.Label, svc.Status, health, formatUptime(svc.StartedAt), cpu, mem})
		}
	}

	appendRows(runningServices)
	appendRows(setupServices)

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
	par.Text = strings.TrimRight(b.String(), "\n")
	par.Border = true
	par.BorderStyle = ui.NewStyle(ui.ColorYellow)
	par.PaddingLeft = 0
	par.PaddingRight = 0
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
	par.Text = strings.TrimRight(b.String(), "\n")
	par.Border = true
	par.BorderStyle = ui.NewStyle(ui.ColorYellow)
	par.PaddingLeft = 0
	par.PaddingRight = 0
	return par
}

func simplifyRepo(repo string) string {
	repo = strings.TrimSpace(repo)
	repo = strings.TrimSuffix(repo, ".git")
	repo = strings.TrimPrefix(repo, "https://")
	repo = strings.TrimPrefix(repo, "http://")
	repo = strings.TrimPrefix(repo, "git@")
	repo = strings.TrimPrefix(repo, "github.com:")
	repo = strings.TrimPrefix(repo, "gitlab.com:")
	repo = strings.TrimPrefix(repo, "github.com/")
	repo = strings.TrimPrefix(repo, "gitlab.com/")
	return repo
}

func buildInfoParagraph(s *Snapshot) *widgets.Paragraph {
	build := s.Build
	var lines []string

	if build.Branch != "" {
		lines = append(lines, fmt.Sprintf("Branch: %s", build.Branch))
	}

	if repo := simplifyRepo(build.Repo); repo != "" {
		lines = append(lines, fmt.Sprintf("Repo: %s", repo))
	}

	commitLine := "Git: unknown"
	if build.Commit != "" {
		commitLine = fmt.Sprintf("Git: %s", build.Commit)
		switch build.CommitSource {
		case "image-label":
			commitLine += " [image]"
		case "source-tree":
			commitLine += " [source]"
		}
	}
	lines = append(lines, commitLine)

	if build.Image != "" {
		// Skip image line to keep header compact
	}

	lines = append(lines, fmt.Sprintf("Updated: %s", s.Timestamp))

	par := widgets.NewParagraph()
	par.Title = "Build"
	par.Text = strings.Join(lines, "\n")
	par.Border = true
	par.BorderStyle = ui.NewStyle(ui.ColorYellow)
	return par
}

func renderSnapshot(s *Snapshot, selectedModule int) (*widgets.List, *ui.Grid) {
	hostname, err := os.Hostname()
	if err != nil || hostname == "" {
		hostname = "unknown"
	}
	ip := primaryIPv4()
	if ip == "" {
		ip = "unknown"
	}

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
	volumesPar := buildVolumesParagraph(s)

	header := widgets.NewParagraph()
	header.Text = fmt.Sprintf("Host: %s\nIP: %s\nProject: %s\nNetwork: %s", hostname, ip, s.Project, s.Network)
	header.Border = true

	buildPar := buildInfoParagraph(s)

	usersPar := widgets.NewParagraph()
	usersPar.Title = "Users"
	usersPar.Text = fmt.Sprintf("  Accounts: %d\n  Online: %d\n  Characters: %d\n  Active 7d: %d", s.Users.Accounts, s.Users.Online, s.Users.Characters, s.Users.Active7d)
	usersPar.Border = true

	grid := ui.NewGrid()
	termWidth, termHeight := ui.TerminalDimensions()
	grid.SetRect(0, 0, termWidth, termHeight)
	grid.Set(
		ui.NewRow(0.18,
			ui.NewCol(0.34, header),
			ui.NewCol(0.33, buildPar),
			ui.NewCol(0.33, usersPar),
		),
		ui.NewRow(0.43,
			ui.NewCol(0.6, servicesTable),
			ui.NewCol(0.4, portsTable),
		),
		ui.NewRow(0.39,
			ui.NewCol(0.25, modulesList),
			ui.NewCol(0.15,
				ui.NewRow(0.32, helpPar),
				ui.NewRow(0.68, moduleInfoPar),
			),
			ui.NewCol(0.6,
				ui.NewRow(0.513,
					ui.NewCol(1.0, storagePar),
				),
				ui.NewRow(0.487,
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
