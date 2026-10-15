"""Checks that molpert and rdkit exchange molecules correctly.

Run against an installed wheel. A build against mismatched RDKit or Boost
headers typically fails here with argument conversion errors or crashes.
"""

from rdkit import Chem, rdBase

import molpert as mpt


def main():
    print(f"molpert {mpt.__file__}, rdkit {rdBase.rdkitVersion}")

    rdBase.DisableLog("rdApp.*")

    molecule = Chem.MolFromSmiles("CC(=O)Nc1ccc(O)cc1CCN")
    mpt.TagMolecule(molecule)
    assert mpt.GetAtomTag(molecule.GetAtomWithIdx(3)) == 3
    assert mpt.GetBondTag(molecule.GetBondWithIdx(2)) == 2

    perturbation = mpt.AtomicNumberChange(atom_idx=0, atomic_number=8)
    copy = Chem.RWMol(molecule)
    mpt.ExecutePerturbation(perturbation, copy)
    assert Chem.MolToSmiles(copy) == "NCCc1cc(O)ccc1NC(=O)O", Chem.MolToSmiles(copy)

    def is_heteroatom(atom):
        return atom.GetAtomicNum() not in (1, 6)

    constraints = mpt.MolecularConstraints()
    constraints.SetBondConstraint(
        bond_tag=2,
        bond_constraint=lambda bond: not (
            is_heteroatom(bond.GetBeginAtom()) and is_heteroatom(bond.GetEndAtom())
        ),
    )
    constraints.SetMoleculeConstraint(
        molecule_constraint=lambda mol: mol.GetNumAtoms() <= 25
    )

    perturber = mpt.MoleculePerturber()
    perturber.SetAtomicNumbers(atomic_numbers=[6, 7, 8], weights=[0.6, 0.2, 0.2])
    prng = mpt.PRNG()

    current = Chem.Mol(molecule)
    n_valid = 0
    for _ in range(2000):
        perturbation = perturber.Perturbation(
            molecule=current, prng=prng, constraints=constraints
        )
        if perturbation is None:
            continue
        candidate = Chem.RWMol(current)
        mpt.ExecutePerturbation(perturbation, candidate)
        try:
            Chem.SanitizeMol(candidate)
        except Exception:
            continue
        current = candidate.GetMol()
        n_valid += 1
    assert n_valid > 100, n_valid

    queue = mpt.MolecularPerturbationQueue()
    perturber.Perturbations(queue=queue, molecule=molecule, constraints=constraints)
    assert len(queue) > 0

    print(f"OK: {n_valid} valid random perturbations, {len(queue)} enumerated")


if __name__ == "__main__":
    main()
