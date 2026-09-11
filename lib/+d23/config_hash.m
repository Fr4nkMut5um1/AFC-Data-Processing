function value = config_hash(cfg)
%CONFIG_HASH Stable run-contract hash excluding the resume pointer.
contract = cfg;
if isfield(contract, 'output') && isfield(contract.output, 'resume_run_dir')
    contract.output.resume_run_dir = '';
end
value = d23.sha256_text(jsonencode(contract));
end
