package v1alpha1

import "k8s.io/apimachinery/pkg/runtime"

func (in *HealingPolicy) DeepCopyInto(out *HealingPolicy) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ObjectMeta.DeepCopyInto(&out.ObjectMeta)
	out.Spec = in.Spec
	out.Status = in.Status
}

func (in *HealingPolicy) DeepCopy() *HealingPolicy {
	if in == nil {
		return nil
	}
	out := new(HealingPolicy)
	in.DeepCopyInto(out)
	return out
}

func (in *HealingPolicy) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}

func (in *HealingPolicyList) DeepCopyInto(out *HealingPolicyList) {
	*out = *in
	out.TypeMeta = in.TypeMeta
	in.ListMeta.DeepCopyInto(&out.ListMeta)
	if in.Items != nil {
		in, out := &in.Items, &out.Items
		*out = make([]HealingPolicy, len(*in))
		for i := range *in {
			(*in)[i].DeepCopyInto(&(*out)[i])
		}
	}
}

func (in *HealingPolicyList) DeepCopy() *HealingPolicyList {
	if in == nil {
		return nil
	}
	out := new(HealingPolicyList)
	in.DeepCopyInto(out)
	return out
}

func (in *HealingPolicyList) DeepCopyObject() runtime.Object {
	if c := in.DeepCopy(); c != nil {
		return c
	}
	return nil
}
