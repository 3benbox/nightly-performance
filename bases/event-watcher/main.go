package main

import (
	"context"
	"fmt"
	"os"
	"path/filepath"
	"time"

	v1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1" // For meta types like ListOptions
	"k8s.io/apimachinery/pkg/watch"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"k8s.io/client-go/tools/clientcmd"
	"k8s.io/client-go/util/homedir" // Corrected import for v1
)

func main() {
	var config *rest.Config
	var err error

	// In-cluster configuration
	config, err = rest.InClusterConfig()
	if err != nil {
		// Fallback to local kubeconfig for development outside of cluster
		if home := homedir.HomeDir(); home != "" {
			kubeconfig := filepath.Join(home, ".kube", "config")
			config, err = clientcmd.BuildConfigFromFlags("", kubeconfig)
			if err != nil {
				panic(err.Error())
			}
		}
	}

	clientset, err := kubernetes.NewForConfig(config)
	if err != nil {
		panic(err.Error())
	}

	// Dynamically determine the current namespace
	namespace, err := getCurrentNamespace()
	if err != nil {
		panic(err.Error())
	}

	watchEvents(clientset, namespace)
}

// getCurrentNamespace reads the namespace from the standard location within a pod
func getCurrentNamespace() (string, error) {
	ns, err := os.ReadFile("/var/run/secrets/kubernetes.io/serviceaccount/namespace")
	if err != nil {
		return "", err
	}
	return string(ns), nil
}

func watchEvents(clientset *kubernetes.Clientset, namespace string) {
	for {
		w, err := clientset.CoreV1().Events(namespace).Watch(context.TODO(), metav1.ListOptions{})
		if err != nil {
			panic(err.Error())
		}

		fmt.Println("Watching events in namespace:", namespace)

		for event := range w.ResultChan() {
			switch event.Type {
			case watch.Added, watch.Modified:
				e := event.Object.(*v1.Event)
				fmt.Printf("Event: %v %v %v %v\n", e.LastTimestamp.Time, e.InvolvedObject.Name, e.Reason, e.Message)
			}
		}

		// Reconnect logic in case of disconnection
		fmt.Println("Reconnecting to watch events after disconnection...")
		time.Sleep(time.Second * 5)
	}
}
