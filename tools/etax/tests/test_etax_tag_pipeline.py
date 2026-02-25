import json
import subprocess
import tempfile
import unittest
from pathlib import Path


class EtaxTagPipelineTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.repo_root = Path(__file__).resolve().parents[3]
        cls.extract_script = cls.repo_root / "scripts" / "etax_extract_tags.py"
        cls.validate_script = cls.repo_root / "scripts" / "etax_validate_tags.py"
        cls.apply_script = cls.repo_root / "scripts" / "etax_apply_tags.py"
        cls.fixture_dir = cls.repo_root / "tools" / "etax" / "fixtures"
        cls.mapping_config = cls.repo_root / "tools" / "etax" / "mapping_rules_2025.json"
        cls.required_keys = cls.repo_root / "tools" / "etax" / "required_internal_keys.json"

    def run_cmd(self, *args: str) -> subprocess.CompletedProcess[str]:
        return subprocess.run(
            list(args),
            cwd=self.repo_root,
            text=True,
            capture_output=True,
            check=False,
        )

    def test_extract_validate_apply_pipeline_success(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            temp_dir = Path(td)
            tag_dict = temp_dir / "TagDictionary_2025.json"
            applied_taxyear_from_extract = temp_dir / "TaxYear2025.extract.json"
            applied_taxyear = temp_dir / "TaxYear2025.applied.json"
            base_taxyear = self.fixture_dir / "base_taxyear_2025.json"

            extract = self.run_cmd(
                "python3",
                str(self.extract_script),
                "--input-dir",
                str(self.fixture_dir),
                "--tax-year",
                "2025",
                "--mapping-config",
                str(self.mapping_config),
                "--out-tag-dict",
                str(tag_dict),
                "--base-taxyear-json",
                str(base_taxyear),
                "--out-taxyear-json",
                str(applied_taxyear_from_extract),
            )
            self.assertEqual(extract.returncode, 0, msg=extract.stderr)
            self.assertTrue(tag_dict.exists(), msg="TagDictionaryが生成されていません")
            self.assertTrue(applied_taxyear_from_extract.exists(), msg="TaxYear反映結果が生成されていません")

            validate = self.run_cmd(
                "python3",
                str(self.validate_script),
                "--taxyear-json",
                str(applied_taxyear_from_extract),
                "--required-keys",
                str(self.required_keys),
            )
            self.assertEqual(validate.returncode, 0, msg=validate.stdout + validate.stderr)

            apply_cmd = self.run_cmd(
                "python3",
                str(self.apply_script),
                "--base-taxyear-json",
                str(base_taxyear),
                "--tag-dict",
                str(tag_dict),
                "--out-taxyear-json",
                str(applied_taxyear),
            )
            self.assertEqual(apply_cmd.returncode, 0, msg=apply_cmd.stdout + apply_cmd.stderr)

            with applied_taxyear.open("r", encoding="utf-8") as fp:
                taxyear = json.load(fp)
            self.assertIn("fields", taxyear)
            self.assertGreater(len(taxyear["fields"]), 0)
            empty_xml_tags = [
                field["internalKey"]
                for field in taxyear["fields"]
                if not str(field.get("xmlTag", "")).strip()
            ]
            self.assertEqual(empty_xml_tags, [], msg=f"空xmlTagが残っています: {empty_xml_tags}")

    def test_extract_fails_when_input_directory_missing(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            tag_dict = Path(td) / "TagDictionary_2025.json"
            result = self.run_cmd(
                "python3",
                str(self.extract_script),
                "--input-dir",
                str(Path(td) / "not-found"),
                "--tax-year",
                "2025",
                "--mapping-config",
                str(self.mapping_config),
                "--out-tag-dict",
                str(tag_dict),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("入力ディレクトリ", result.stderr)

    def test_validate_detects_missing_required_keys(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            temp_dir = Path(td)
            invalid_taxyear = temp_dir / "TaxYear2025.invalid.json"
            with (self.fixture_dir / "base_taxyear_2025.json").open("r", encoding="utf-8") as fp:
                taxyear = json.load(fp)
            # 必須キーを1件削除して失敗を再現
            taxyear["fields"] = [f for f in taxyear["fields"] if f["internalKey"] != "revenue_sales_revenue"]
            with invalid_taxyear.open("w", encoding="utf-8") as fp:
                json.dump(taxyear, fp, ensure_ascii=False, indent=2)
                fp.write("\n")

            validate = self.run_cmd(
                "python3",
                str(self.validate_script),
                "--taxyear-json",
                str(invalid_taxyear),
                "--required-keys",
                str(self.required_keys),
            )
            self.assertNotEqual(validate.returncode, 0)
            self.assertIn("required internalKey が不足", validate.stdout)

    def test_apply_fails_on_missing_without_allow_missing_flag(self) -> None:
        with tempfile.TemporaryDirectory() as td:
            temp_dir = Path(td)
            partial_tag_dict = temp_dir / "TagDictionary.partial.json"
            out_taxyear = temp_dir / "TaxYear2025.out.json"

            payload = {
                "taxYear": 2025,
                "generatedAt": "2026-01-01T00:00:00Z",
                "sourceDirectory": str(temp_dir),
                "itemCount": 1,
                "items": [
                    {
                        "internalKey": "revenue_sales_revenue",
                        "xmlTag": "BlueRevenueSales",
                        "dataType": "number",
                        "sourceFile": "dummy.csv",
                        "sourceSheet": "csv",
                        "sourceRow": 2,
                    }
                ],
            }
            with partial_tag_dict.open("w", encoding="utf-8") as fp:
                json.dump(payload, fp, ensure_ascii=False, indent=2)
                fp.write("\n")

            result = self.run_cmd(
                "python3",
                str(self.apply_script),
                "--base-taxyear-json",
                str(self.fixture_dir / "base_taxyear_2025.json"),
                "--tag-dict",
                str(partial_tag_dict),
                "--out-taxyear-json",
                str(out_taxyear),
            )
            self.assertNotEqual(result.returncode, 0)
            self.assertIn("TagDictionaryに存在しないinternalKey", result.stderr)


if __name__ == "__main__":
    unittest.main()
