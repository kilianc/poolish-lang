package tempdir

import (
	"os"
	"path/filepath"
	"testing"
)

func WriteFiles(fsroot string, files map[string]string, t *testing.T) {
	t.Helper()

	for path, content := range files {
		path = filepath.Join(fsroot, path)

		err := os.MkdirAll(filepath.Dir(path), 0o755)
		if err != nil {
			t.Fatalf("MkdirAll(%s): %v", path, err)
		}

		err = os.WriteFile(path, []byte(content), 0o644)
		if err != nil {
			t.Fatalf("WriteFile(%s): %v", path, err)
		}
	}
}
