package operator_test

import (
	"context"
	"flag"
	"io"
	"testing"
	"time"

	"github.com/stretchr/testify/require"
	corev1 "k8s.io/api/core/v1"
	apimeta "k8s.io/apimachinery/pkg/api/meta"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"sigs.k8s.io/controller-runtime/pkg/client"

	"github.com/AtomiCloud/diene.fleet-operator/adapters/operator/controllers"
	"github.com/AtomiCloud/diene.fleet-operator/adapters/operator/metrics"
	apiv1alpha1 "github.com/AtomiCloud/diene.fleet-operator/api/v1alpha1"
	"github.com/AtomiCloud/diene.fleet-operator/internal/operatorruntime"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/ledger"
	"github.com/AtomiCloud/diene.fleet-operator/lib/operator/plan"
)

func TestMultiControllerWiring(t *testing.T) {
	config := operatorruntime.Config{}
	flags := flag.NewFlagSet("manager-acceptance", flag.ContinueOnError)
	flags.SetOutput(io.Discard)
	operatorruntime.BindFlags(flags, &config)
	require.NoError(t, flags.Parse([]string{
		"--enable-note=true",
		"--enable-journal=true",
		"--leader-elect=false",
		"--metrics-bind-address=0",
		"--health-probe-bind-address=0",
		"--blast-brake-cap=20",
		"--platform=diene",
		"--landscape=lapras",
	}))
	require.True(t, config.EnableNote)
	require.True(t, config.EnableJournal)
	require.False(t, config.LeaderElection)

	manager, err := operatorruntime.NewManager(restConfig, testScheme, config)
	require.NoError(t, err)
	noteLedger := ledger.NewService(newFakeLedgerStore())
	require.NoError(t, operatorruntime.RegisterControllers(manager, config, operatorruntime.ControllerDependencies{
		Clock:      fakeClock{t: time.Unix(1700000000, 0).UTC()},
		Metrics:    metrics.NewPrometheus(),
		NoteLedger: &noteLedger,
	}))

	managerContext, stopManager := context.WithCancel(context.Background())
	managerDone := make(chan error, 1)
	go func() {
		managerDone <- manager.Start(managerContext)
	}()
	t.Cleanup(func() {
		stopManager()
		require.NoError(t, <-managerDone)
	})

	cacheContext, stopCacheWait := context.WithTimeout(managerContext, 10*time.Second)
	defer stopCacheWait()
	require.True(t, manager.GetCache().WaitForCacheSync(cacheContext))

	note := &apiv1alpha1.Note{
		ObjectMeta: metav1.ObjectMeta{Name: "manager-note", Namespace: "default"},
		Spec: apiv1alpha1.NoteSpec{
			Title:    "Manager Note",
			Body:     "converged through enabled registration",
			Category: "work",
			Replicas: 1,
		},
	}
	journal := &apiv1alpha1.Journal{
		ObjectMeta: metav1.ObjectMeta{Name: "manager-journal", Namespace: "default"},
		Spec:       apiv1alpha1.JournalSpec{Message: "converged independently"},
	}
	require.NoError(t, k8sClient.Create(context.Background(), note))
	require.NoError(t, k8sClient.Create(context.Background(), journal))

	require.Eventually(t, func() bool {
		var current apiv1alpha1.Note
		if err := k8sClient.Get(context.Background(), client.ObjectKeyFromObject(note), &current); err != nil {
			return false
		}
		ready := apimeta.FindStatusCondition(current.Status.Conditions, plan.TypeReady)
		return ready != nil && ready.Status == metav1.ConditionTrue && current.Status.OwnedConfigMaps == 1
	}, 15*time.Second, 100*time.Millisecond, "enabled Note controller did not converge")

	require.Eventually(t, func() bool {
		var current apiv1alpha1.Journal
		if err := k8sClient.Get(context.Background(), client.ObjectKeyFromObject(journal), &current); err != nil {
			return false
		}
		ready := apimeta.FindStatusCondition(current.Status.Conditions, plan.TypeReady)
		return ready != nil && ready.Status == metav1.ConditionTrue
	}, 15*time.Second, 100*time.Millisecond, "enabled Journal controller did not converge")

	var owned corev1.ConfigMapList
	require.NoError(t, k8sClient.List(
		context.Background(), &owned,
		client.InNamespace("default"),
		client.MatchingLabels{controllers.NoteOwnerLabel: note.Name},
	))
	require.Len(t, owned.Items, 1)
}
