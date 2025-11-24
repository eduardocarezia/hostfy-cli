package docker

import (
	"context"
	"fmt"
	"io"
	"os"
	"os/exec"
	"strings"
	"time"

	"github.com/docker/docker/api/types/container"
	"github.com/docker/docker/api/types/filters"
	"github.com/docker/docker/api/types/image"
	"github.com/docker/docker/api/types/network"
	"github.com/docker/docker/client"
	"github.com/docker/go-connections/nat"
)

const (
	NetworkName = "hostfy_network"
)

type Client struct {
	cli *client.Client
	ctx context.Context
}

func NewClient() (*Client, error) {
	cli, err := client.NewClientWithOpts(client.FromEnv, client.WithAPIVersionNegotiation())
	if err != nil {
		return nil, fmt.Errorf("erro ao conectar ao Docker: %w", err)
	}

	return &Client{
		cli: cli,
		ctx: context.Background(),
	}, nil
}

func (c *Client) Close() {
	c.cli.Close()
}

func (c *Client) EnsureNetwork() error {
	networks, err := c.cli.NetworkList(c.ctx, network.ListOptions{
		Filters: filters.NewArgs(filters.Arg("name", NetworkName)),
	})
	if err != nil {
		return err
	}

	if len(networks) > 0 {
		return nil
	}

	_, err = c.cli.NetworkCreate(c.ctx, NetworkName, network.CreateOptions{
		Driver: "bridge",
	})
	return err
}

func (c *Client) PullImage(imageName string) error {
	reader, err := c.cli.ImagePull(c.ctx, imageName, image.PullOptions{})
	if err != nil {
		return err
	}
	defer reader.Close()
	io.Copy(io.Discard, reader)
	return nil
}

func (c *Client) ContainerExists(name string) (bool, error) {
	containers, err := c.cli.ContainerList(c.ctx, container.ListOptions{
		All:     true,
		Filters: filters.NewArgs(filters.Arg("name", "^/"+name+"$")),
	})
	if err != nil {
		return false, err
	}
	return len(containers) > 0, nil
}

func (c *Client) ContainerRunning(name string) (bool, error) {
	containers, err := c.cli.ContainerList(c.ctx, container.ListOptions{
		Filters: filters.NewArgs(filters.Arg("name", "^/"+name+"$")),
	})
	if err != nil {
		return false, err
	}
	return len(containers) > 0, nil
}

func (c *Client) GetContainerID(name string) (string, error) {
	containers, err := c.cli.ContainerList(c.ctx, container.ListOptions{
		All:     true,
		Filters: filters.NewArgs(filters.Arg("name", "^/"+name+"$")),
	})
	if err != nil {
		return "", err
	}
	if len(containers) == 0 {
		return "", fmt.Errorf("container %s não encontrado", name)
	}
	return containers[0].ID, nil
}

type ContainerConfig struct {
	Name        string
	Image       string
	Env         map[string]string
	Volumes     []string
	Ports       map[string]string // container:host
	Labels      map[string]string
	Command     []string
	NetworkName string
	Restart     string
}

func (c *Client) CreateContainer(cfg *ContainerConfig) (string, error) {
	envList := make([]string, 0, len(cfg.Env))
	for k, v := range cfg.Env {
		envList = append(envList, k+"="+v)
	}

	exposedPorts := nat.PortSet{}
	portBindings := nat.PortMap{}
	for containerPort, hostPort := range cfg.Ports {
		port := nat.Port(containerPort + "/tcp")
		exposedPorts[port] = struct{}{}
		portBindings[port] = []nat.PortBinding{
			{HostIP: "0.0.0.0", HostPort: hostPort},
		}
	}

	binds := make([]string, 0, len(cfg.Volumes))
	for _, vol := range cfg.Volumes {
		binds = append(binds, vol)
	}

	restartPolicy := container.RestartPolicy{Name: "unless-stopped"}
	if cfg.Restart == "always" {
		restartPolicy.Name = "always"
	}

	networkName := cfg.NetworkName
	if networkName == "" {
		networkName = NetworkName
	}

	containerCfg := &container.Config{
		Image:        cfg.Image,
		Env:          envList,
		ExposedPorts: exposedPorts,
		Labels:       cfg.Labels,
	}

	if len(cfg.Command) > 0 {
		containerCfg.Cmd = cfg.Command
	}

	hostCfg := &container.HostConfig{
		Binds:         binds,
		PortBindings:  portBindings,
		RestartPolicy: restartPolicy,
		NetworkMode:   container.NetworkMode(networkName),
	}

	networkCfg := &network.NetworkingConfig{
		EndpointsConfig: map[string]*network.EndpointSettings{
			networkName: {},
		},
	}

	resp, err := c.cli.ContainerCreate(c.ctx, containerCfg, hostCfg, networkCfg, nil, cfg.Name)
	if err != nil {
		return "", err
	}

	return resp.ID, nil
}

func (c *Client) StartContainer(id string) error {
	return c.cli.ContainerStart(c.ctx, id, container.StartOptions{})
}

func (c *Client) StopContainer(name string) error {
	timeout := 30
	return c.cli.ContainerStop(c.ctx, name, container.StopOptions{Timeout: &timeout})
}

func (c *Client) RemoveContainer(name string, force bool) error {
	return c.cli.ContainerRemove(c.ctx, name, container.RemoveOptions{
		Force:         force,
		RemoveVolumes: false,
	})
}

func (c *Client) RestartContainer(name string) error {
	timeout := 30
	return c.cli.ContainerRestart(c.ctx, name, container.StopOptions{Timeout: &timeout})
}

func (c *Client) WaitForHealthy(name string, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for time.Now().Before(deadline) {
		inspect, err := c.cli.ContainerInspect(c.ctx, name)
		if err != nil {
			time.Sleep(2 * time.Second)
			continue
		}

		if inspect.State.Health != nil {
			if inspect.State.Health.Status == "healthy" {
				return nil
			}
		} else if inspect.State.Running {
			time.Sleep(3 * time.Second)
			return nil
		}

		time.Sleep(2 * time.Second)
	}
	return fmt.Errorf("timeout aguardando %s ficar healthy", name)
}

func (c *Client) GetContainerLogs(name string, tail string, follow bool) (io.ReadCloser, error) {
	return c.cli.ContainerLogs(c.ctx, name, container.LogsOptions{
		ShowStdout: true,
		ShowStderr: true,
		Tail:       tail,
		Follow:     follow,
	})
}

func (c *Client) UpdateContainerImage(name, newImage string) error {
	inspect, err := c.cli.ContainerInspect(c.ctx, name)
	if err != nil {
		return err
	}

	if err := c.StopContainer(name); err != nil {
		return err
	}

	if err := c.RemoveContainer(name, false); err != nil {
		return err
	}

	if err := c.PullImage(newImage); err != nil {
		return err
	}

	env := make(map[string]string)
	for _, e := range inspect.Config.Env {
		parts := strings.SplitN(e, "=", 2)
		if len(parts) == 2 {
			env[parts[0]] = parts[1]
		}
	}

	var binds []string
	if inspect.HostConfig != nil {
		binds = inspect.HostConfig.Binds
	}

	ports := make(map[string]string)
	if inspect.HostConfig != nil {
		for p, b := range inspect.HostConfig.PortBindings {
			if len(b) > 0 {
				ports[p.Port()] = b[0].HostPort
			}
		}
	}

	cfg := &ContainerConfig{
		Name:    name,
		Image:   newImage,
		Env:     env,
		Volumes: binds,
		Ports:   ports,
		Labels:  inspect.Config.Labels,
		Restart: "always",
	}

	id, err := c.CreateContainer(cfg)
	if err != nil {
		return err
	}

	return c.StartContainer(id)
}

func ExecCommand(name string, command []string) (string, error) {
	args := append([]string{"exec", name}, command...)
	cmd := exec.Command("docker", args...)
	output, err := cmd.CombinedOutput()
	return string(output), err
}

func CreateDatabase(containerName, dbName, user string) error {
	cmd := exec.Command("docker", "exec", containerName, "psql", "-U", user, "-c",
		fmt.Sprintf("CREATE DATABASE %s;", dbName))
	cmd.Stdout = os.Stdout
	cmd.Stderr = os.Stderr
	err := cmd.Run()
	if err != nil && !strings.Contains(err.Error(), "already exists") {
		return err
	}
	return nil
}
